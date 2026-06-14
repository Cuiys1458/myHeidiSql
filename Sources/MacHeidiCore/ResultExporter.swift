import Foundation

/// ResultSet → CSV / SQL 文本导出（PRD §11 v0.2）。
///
/// 纯函数，不接 IO。调用方决定写入文件 / 剪贴板。
public enum ResultExporter {

    public enum Format: String, CaseIterable, Sendable {
        case csv  = "CSV"
        case tsv  = "TSV"
        case sql  = "SQL"
    }

    /// 导出为 CSV。
    /// - 字段中的引号双写（RFC 4180）；含分隔符/换行符的字段加引号包裹。
    /// - NULL → 空字段（CSV 里无 NULL 概念；可由 caller 改为 "\\N" 等）。
    public static func toCSV(_ rs: ResultSet, separator: Character = ",") -> String {
        var out = ""
        // header
        let header = rs.columns.map { escapeCSV($0.name, sep: separator) }
        out.append(header.joined(separator: String(separator)))
        out.append("\n")
        // rows
        for row in rs.rows {
            let parts = row.map { cell -> String in
                if case .null = cell { return "" }
                return escapeCSV(plainString(cell), sep: separator)
            }
            out.append(parts.joined(separator: String(separator)))
            out.append("\n")
        }
        return out
    }

    /// 导出为 TSV（Tab 分隔）。
    public static func toTSV(_ rs: ResultSet) -> String {
        toCSV(rs, separator: "\t")
    }

    /// 导出为可重放的 INSERT 语句序列。
    public static func toSQL(_ rs: ResultSet,
                              database: String?,
                              table: String) -> String {
        guard !rs.rows.isEmpty else {
            return "-- empty result set\n"
        }
        var out = ""
        let qualified: String = {
            if let db = database, let q = try? SQLIdentifier.qualified(database: db, table: table) {
                return q
            }
            return (try? SQLIdentifier.quote(table)) ?? "`\(table)`"
        }()
        let cols = rs.columns.map { (try? SQLIdentifier.quote($0.name)) ?? $0.name }
        let colList = cols.joined(separator: ", ")

        for row in rs.rows {
            let vals = row.map { SQLGenerator.literal($0) }
            out.append("INSERT INTO \(qualified) (\(colList)) VALUES (\(vals.joined(separator: ", ")));\n")
        }
        return out
    }

    /// 流式追加：把一个 ResultSet 块以指定格式追加写到文件。
    /// 第一块写 header，后续只追加 rows。
    /// 用于"导出全表"等场景，避免把百万行整段加载到内存。
    public static func appendChunk(
        to fileHandle: FileHandle,
        chunk: ResultSet,
        format: Format,
        isFirstChunk: Bool,
        database: String?,
        table: String?,
        separator: Character = ","
    ) throws {
        let text: String
        switch format {
        case .csv, .tsv:
            let sep: Character = (format == .tsv) ? "\t" : separator
            var s = ""
            if isFirstChunk {
                let header = chunk.columns.map { escapeCSV($0.name, sep: sep) }
                s.append(header.joined(separator: String(sep)))
                s.append("\n")
            }
            for row in chunk.rows {
                let parts = row.map { cell -> String in
                    if case .null = cell { return "" }
                    return escapeCSV(plainString(cell), sep: sep)
                }
                s.append(parts.joined(separator: String(sep)))
                s.append("\n")
            }
            text = s

        case .sql:
            guard let table = table else {
                throw ExportError.missingTable
            }
            var s = ""
            let qualified: String = {
                if let db = database,
                   let q = try? SQLIdentifier.qualified(database: db, table: table) {
                    return q
                }
                return (try? SQLIdentifier.quote(table)) ?? "`\(table)`"
            }()
            let cols = chunk.columns.map { (try? SQLIdentifier.quote($0.name)) ?? $0.name }
            let colList = cols.joined(separator: ", ")
            for row in chunk.rows {
                let vals = row.map { SQLGenerator.literal($0) }
                s.append("INSERT INTO \(qualified) (\(colList)) VALUES (\(vals.joined(separator: ", ")));\n")
            }
            text = s
        }
        guard let data = text.data(using: .utf8) else { return }
        try fileHandle.write(contentsOf: data)
    }

    public enum ExportError: Error {
        case missingTable
    }


    private static func escapeCSV(_ s: String, sep: Character) -> String {
        if s.contains("\"") || s.contains(sep) || s.contains("\n") || s.contains("\r") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }

    private static func plainString(_ cell: CellValue) -> String {
        switch cell {
        case .null:           return ""
        case .int(let v):     return String(v)
        case .uint(let v):    return String(v)
        case .double(let v):  return String(v)
        case .decimal(let s): return s
        case .string(let s):  return s
        case .bool(let b):    return b ? "true" : "false"
        case .date(let d), .datetime(let d):
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = .current
            return f.string(from: d)
        case .time(let s):    return s
        case .blob(let d):
            // BLOB-as-JSON：导出为 JSON 字符串（可被重新导入 / 在文本工具里查看）
            if let s = JSONHelper.looksLikeJSONBLOB(d) { return s }
            return "[BLOB \(d.count) bytes]"
        case .json(let s):    return s
        case .unknown(let s): return s
        }
    }
}
