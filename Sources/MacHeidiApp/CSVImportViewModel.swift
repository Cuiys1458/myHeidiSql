import Foundation
import AppKit
import Observation
import MacHeidiCore

/// CSV 导入向导的 ViewModel。
///
/// 流程：选文件 → 解析 + 预览 → 列映射 → 流式 INSERT。
@MainActor
@Observable
final class CSVImportViewModel: Identifiable {

    let id = UUID()

    // MARK: 输入

    let database: String
    let table: String
    let schema: TableSchema

    // MARK: 解析状态

    private(set) var fileURL: URL?
    private(set) var fileName: String = ""
    private(set) var separator: Character = ","
    private(set) var hasHeader: Bool = true
    private(set) var preview: [[String]] = []
    private(set) var totalRows: Int = 0
    private(set) var parseError: String?

    // CSV 列名（来自首行 or 自动 Column 1/2/...）
    private(set) var csvColumns: [String] = []

    // MARK: 列映射

    /// 表列名 → CSV 列索引（nil = 不导入此列）
    var mapping: [String: Int?] = [:]

    // MARK: 导入状态

    private(set) var importing: Bool = false
    private(set) var importProgress: Int = 0
    private(set) var importTotal: Int = 0
    private(set) var importDone: Bool = false
    private(set) var importError: String?
    private(set) var importedRows: Int = 0

    init(database: String, table: String, schema: TableSchema) {
        self.database = database
        self.table = table
        self.schema = schema
    }

    // MARK: 文件加载

    func setFile(_ url: URL, separator: Character = ",", hasHeader: Bool = true) {
        self.fileURL = url
        self.fileName = url.lastPathComponent
        self.separator = separator
        self.hasHeader = hasHeader
        reparse()
    }

    func setSeparator(_ s: Character) {
        self.separator = s
        reparse()
    }
    func setHasHeader(_ b: Bool) {
        self.hasHeader = b
        reparse()
    }

    private func reparse() {
        guard let url = fileURL else { return }
        parseError = nil
        preview = []
        csvColumns = []
        totalRows = 0
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                parseError = "Cannot decode file as UTF-8 or Latin-1"
                return
            }
            let rows = try CSVParser.parse(text, separator: separator)
            guard !rows.isEmpty else {
                parseError = "File is empty"
                return
            }
            if hasHeader {
                csvColumns = rows[0]
                preview = Array(rows.dropFirst().prefix(20))
                totalRows = rows.count - 1
            } else {
                let n = rows[0].count
                csvColumns = (0..<n).map { "Column \($0 + 1)" }
                preview = Array(rows.prefix(20))
                totalRows = rows.count
            }
            // 自动建议映射：CSV 列名 == 表列名 时自动选中
            mapping = [:]
            for col in schema.columns {
                if let idx = csvColumns.firstIndex(where: {
                    $0.lowercased() == col.name.lowercased()
                }) {
                    mapping[col.name] = idx
                } else {
                    mapping[col.name] = nil as Int?
                }
            }
        } catch let e as CSVParser.ParseError {
            switch e {
            case .unterminatedQuote(let l):
                parseError = "Unterminated quoted field at line \(l)"
            }
        } catch {
            parseError = String(describing: error)
        }
    }

    // MARK: 校验

    /// 哪些非空列没映射但又是 NOT NULL 且无默认值
    var missingRequiredColumns: [String] {
        schema.columns
            .filter { !$0.nullable && !$0.isAutoIncrement && $0.defaultValue == nil }
            .filter { mapping[$0.name].flatMap { $0 } == nil }
            .map(\.name)
    }

    var canImport: Bool {
        fileURL != nil && parseError == nil && missingRequiredColumns.isEmpty
            && mapping.values.contains { $0 != nil }
    }

    // MARK: 执行导入

    func performImport(env: AppEnvironment, batchSize: Int = 500) async {
        guard let url = fileURL, canImport else { return }
        importing = true
        importDone = false
        importError = nil
        importProgress = 0
        importedRows = 0
        defer { importing = false }

        guard let client = env.activeClient else {
            importError = "Not connected"
            return
        }

        // 重新解析全文（preview 只前 20 行）
        let allRows: [[String]]
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                importError = "Cannot decode file"; return
            }
            let parsed = try CSVParser.parse(text, separator: separator)
            allRows = hasHeader ? Array(parsed.dropFirst()) : parsed
        } catch {
            importError = String(describing: error)
            return
        }
        importTotal = allRows.count

        // 解析映射：表列名 → CSV idx
        let activeColumns: [(ColumnMeta, Int)] = schema.columns.compactMap { col in
            if let idx = mapping[col.name].flatMap({ $0 }) { return (col, idx) }
            return nil
        }
        guard !activeColumns.isEmpty else {
            importError = "No columns mapped"; return
        }

        let qualified: String
        do { qualified = try SQLIdentifier.qualified(database: database, table: table) }
        catch { importError = "Invalid table name"; return }

        let colsSQL = activeColumns
            .map { (try? SQLIdentifier.quote($0.0.name)) ?? $0.0.name }
            .joined(separator: ", ")

        // 分批 INSERT INTO ... VALUES (...), (...), ...
        var batch: [[String]] = []
        do {
            _ = try await client.exec("START TRANSACTION")
            for row in allRows {
                batch.append(row)
                if batch.count >= batchSize {
                    try await flush(client: client, qualified: qualified,
                                     colsSQL: colsSQL, activeColumns: activeColumns,
                                     rows: batch)
                    importProgress += batch.count
                    importedRows += batch.count
                    batch = []
                }
            }
            if !batch.isEmpty {
                try await flush(client: client, qualified: qualified,
                                 colsSQL: colsSQL, activeColumns: activeColumns,
                                 rows: batch)
                importProgress += batch.count
                importedRows += batch.count
            }
            _ = try await client.exec("COMMIT")
            importDone = true
        } catch let e as DBError {
            _ = try? await client.exec("ROLLBACK")
            importError = describe(e)
        } catch {
            _ = try? await client.exec("ROLLBACK")
            importError = String(describing: error)
        }
    }

    private func flush(
        client: any DBClient,
        qualified: String,
        colsSQL: String,
        activeColumns: [(ColumnMeta, Int)],
        rows: [[String]]
    ) async throws {
        var valueBlocks: [String] = []
        for row in rows {
            var values: [String] = []
            for (col, csvIdx) in activeColumns {
                let raw = (csvIdx < row.count) ? row[csvIdx] : ""
                let cell = parseCell(raw, column: col)
                values.append(SQLGenerator.literal(cell))
            }
            valueBlocks.append("(\(values.joined(separator: ", ")))")
        }
        let sql = "INSERT INTO \(qualified) (\(colsSQL)) VALUES \(valueBlocks.joined(separator: ", "))"
        _ = try await client.exec(sql)
    }

    /// CSV 字段（字符串）→ CellValue
    /// - 空字符串 + nullable → NULL
    /// - 否则用 CellValueParser.parse
    /// - 解析失败 fallback 为 .string（让 MySQL 自己抛错而不是这里 throw）
    private func parseCell(_ raw: String, column: ColumnMeta) -> CellValue {
        if raw.isEmpty && column.nullable {
            return .null
        }
        if let v = try? CellValueParser.parse(raw, column: column) {
            return v
        }
        return .string(raw)
    }

    private func describe(_ e: DBError) -> String {
        switch e {
        case .syntax(let n, _, let m): return "ERROR \(n): \(m)"
        case .constraint(let n, _, let m): return "CONSTRAINT \(n): \(m)"
        case .auth(let m, _): return "AUTH: \(m)"
        case .network(let m, _): return "NETWORK: \(m)"
        default: return String(describing: e)
        }
    }
}
