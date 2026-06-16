import SwiftUI
import AppKit
import MacHeidiCore

/// CSV → 新表 向导。
///
/// 与 `CSVImportView` 不同：那个是导入到**已存在**的表（要选列映射）；
/// 这个是从零建表，靠 `CSVTableInferrer` 自动推导 schema，用户改改类型，
/// 一键 CREATE TABLE + INSERT。
struct CSVImportNewTableView: View {
    let database: String
    let onDone: () -> Void
    @Environment(AppEnvironment.self) private var env

    @State private var fileURL: URL?
    @State private var fileName: String = ""
    @State private var separator: Character = ","
    @State private var hasHeader: Bool = true
    @State private var newTableName: String = ""

    @State private var csvHeader: [String] = []
    @State private var csvPreview: [[String]] = []
    @State private var csvAllRows: [[String]] = []
    @State private var totalRows: Int = 0
    @State private var inferred: CSVTableInferrer.Spec?
    @State private var editedTypes: [String: String] = [:]   // cleanName → mysqlType（用户可改）
    @State private var editedNullable: [String: Bool] = [:]  // cleanName → nullable
    @State private var parseError: String?

    @State private var working: Bool = false
    @State private var importProgress: Int = 0
    @State private var importTotal: Int = 0
    @State private var doneMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fileSection
                    if !csvHeader.isEmpty {
                        Divider()
                        nameSection
                        Divider()
                        previewSection
                        if let spec = inferred {
                            Divider()
                            typesSection(spec: spec)
                            Divider()
                            createSQLSection(spec: spec)
                        }
                    }
                    if let msg = doneMessage {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                    if let msg = errorMessage {
                        Label(msg, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
    }

    // MARK: header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells.badge.ellipsis")
                .foregroundStyle(Color.accentColor)
            Text(String(format: NSLocalizedString(
                "csvNew.title", bundle: .module, comment: ""
            ), database))
                .font(.headline.monospaced())
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: 1. 选文件

    @ViewBuilder
    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("csvNew.step1")).font(.subheadline.bold())
            HStack(spacing: 12) {
                Button {
                    pickFile()
                } label: {
                    Label(L("csv.pickFile"), systemImage: "folder")
                }
                if !fileName.isEmpty {
                    Text(fileName)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 12) {
                Picker("", selection: separatorPickerBinding) {
                    Text(",").tag(Character(","))
                    Text("\\t").tag(Character("\t"))
                    Text(";").tag(Character(";"))
                    Text("|").tag(Character("|"))
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Toggle(L("csvNew.firstHeader"), isOn: hasHeaderBinding)
                    .toggleStyle(.checkbox)
                Spacer()
                Text("\(totalRows) rows")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let err = parseError {
                Text(err).foregroundStyle(.red).font(.caption.monospaced())
            }
        }
    }

    private var separatorPickerBinding: Binding<Character> {
        Binding(get: { separator }, set: { newVal in
            separator = newVal
            reparse()
        })
    }
    private var hasHeaderBinding: Binding<Bool> {
        Binding(get: { hasHeader }, set: { newVal in
            hasHeader = newVal
            reparse()
        })
    }

    // MARK: 2. 表名

    @ViewBuilder
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("csvNew.step2")).font(.subheadline.bold())
            HStack(spacing: 12) {
                Text(L("csvNew.tableName")).font(.caption)
                TextField("", text: $newTableName,
                          prompt: Text(L("csvNew.tableNamePh")))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                    .onChange(of: newTableName) { _, _ in regenerateSpec() }
            }
        }
    }

    // MARK: 数据预览

    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("csvNew.previewLabel")).font(.subheadline.bold())
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(csvHeader.enumerated()), id: \.offset) { _, h in
                            Text(h)
                                .font(.caption.bold().monospaced())
                                .frame(width: 140, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                        }
                    }
                    Divider()
                    ForEach(Array(csvPreview.prefix(5).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(.caption.monospaced())
                                    .frame(width: 140, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: 推导出的列（可改类型）

    @ViewBuilder
    private func typesSection(spec: CSVTableInferrer.Spec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("csvNew.inferredCols")).font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(L("csvNew.colName")).font(.caption.bold())
                        .frame(width: 200, alignment: .leading)
                        .padding(.horizontal, 8)
                    Text(L("csvNew.colType")).font(.caption.bold())
                        .frame(width: 220, alignment: .leading)
                        .padding(.horizontal, 8)
                    Text(L("csvNew.colNullable")).font(.caption.bold())
                        .frame(width: 80, alignment: .leading)
                        .padding(.horizontal, 8)
                }
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                Divider()
                ForEach(Array(spec.columns.enumerated()), id: \.offset) { idx, col in
                    HStack(spacing: 0) {
                        Text(col.cleanName)
                            .font(.callout.monospaced())
                            .frame(width: 200, alignment: .leading)
                            .padding(.horizontal, 8)
                        TextField("", text: typeBinding(for: col))
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                            .frame(width: 200)
                            .padding(.horizontal, 8)
                        Toggle("", isOn: nullableBinding(for: col))
                            .labelsHidden()
                            .frame(width: 80, alignment: .leading)
                            .padding(.horizontal, 8)
                    }
                    .padding(.vertical, 3)
                    .background(idx % 2 != 0 ? Color.primary.opacity(0.04) : Color.clear)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    private func typeBinding(for col: CSVTableInferrer.ColumnSpec) -> Binding<String> {
        Binding(
            get: { editedTypes[col.cleanName] ?? col.mysqlType },
            set: { editedTypes[col.cleanName] = $0 }
        )
    }
    private func nullableBinding(for col: CSVTableInferrer.ColumnSpec) -> Binding<Bool> {
        Binding(
            get: { editedNullable[col.cleanName] ?? col.nullable },
            set: { editedNullable[col.cleanName] = $0 }
        )
    }

    // MARK: 3. CREATE TABLE 预览

    @ViewBuilder
    private func createSQLSection(spec: CSVTableInferrer.Spec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("csvNew.createSQL")).font(.subheadline.bold())
            ScrollView {
                Text(effectiveCreateSQL(spec: spec))
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 160)
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    /// 用户改过 type / nullable 后重新拼 SQL（spec.createSQL 是初始值）。
    /// 主键策略与 `CSVTableInferrer` 一致：
    /// - spec.primaryKeyColumn != nil → 用该列作 PK，不注入隐式 id
    /// - 否则注入 BIGINT AUTO_INCREMENT id
    private func effectiveCreateSQL(spec: CSVTableInferrer.Spec) -> String {
        guard let qualified = try? SQLIdentifier.qualified(database: database, table: newTableName) else {
            return spec.createSQL
        }
        var lines: [String] = []
        if let pkName = spec.primaryKeyColumn,
           let pkCol = spec.columns.first(where: { $0.cleanName == pkName }) {
            // CSV 已自带 id 列：把它作 PRIMARY KEY，强制 NOT NULL
            let type = editedTypes[pkCol.cleanName] ?? pkCol.mysqlType
            let qc = (try? SQLIdentifier.quote(pkCol.cleanName)) ?? pkCol.cleanName
            lines.append("\(qc) \(type) NOT NULL PRIMARY KEY")
            for c in spec.columns where c.cleanName != pkName {
                let type = editedTypes[c.cleanName] ?? c.mysqlType
                let null = editedNullable[c.cleanName] ?? c.nullable
                let qc = (try? SQLIdentifier.quote(c.cleanName)) ?? c.cleanName
                lines.append("\(qc) \(type) \(null ? "NULL" : "NOT NULL")")
            }
        } else {
            // 注入隐式自增 id
            lines.append("`id` BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY")
            for c in spec.columns {
                let type = editedTypes[c.cleanName] ?? c.mysqlType
                let null = editedNullable[c.cleanName] ?? c.nullable
                let qc = (try? SQLIdentifier.quote(c.cleanName)) ?? c.cleanName
                lines.append("\(qc) \(type) \(null ? "NULL" : "NOT NULL")")
            }
        }
        let body = lines.joined(separator: ",\n  ")
        return "CREATE TABLE \(qualified) (\n  \(body)\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    }

    // MARK: footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            if working, importTotal > 0 {
                ProgressView(value: Double(importProgress), total: Double(importTotal))
                    .frame(width: 200)
                Text(String(format: NSLocalizedString(
                    "csvNew.importing", bundle: .module, comment: ""
                ), importProgress, importTotal))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("csvNew.cancel")) { onDone() }
                .keyboardShortcut(.cancelAction)
                .disabled(working)
            Button(L("csvNew.createAndImport")) {
                Task { await createAndImport() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(working || inferred == nil
                      || newTableName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: 业务逻辑

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        fileName = url.lastPathComponent
        if newTableName.isEmpty {
            // 用文件名（去后缀）作为默认表名
            newTableName = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
        }
        reparse()
    }

    private func reparse() {
        guard let url = fileURL else { return }
        parseError = nil
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                parseError = "Cannot decode file"
                return
            }
            let parsed = try CSVParser.parse(text, separator: separator)
            guard !parsed.isEmpty else {
                parseError = "Empty file"
                return
            }
            if hasHeader {
                csvHeader = parsed[0]
                csvPreview = Array(parsed.dropFirst().prefix(20))
                csvAllRows = Array(parsed.dropFirst())
                totalRows = parsed.count - 1
            } else {
                let n = parsed[0].count
                csvHeader = (0..<n).map { "Column \($0 + 1)" }
                csvPreview = Array(parsed.prefix(20))
                csvAllRows = parsed
                totalRows = parsed.count
            }
            // 推导一次（基于最多 200 行采样）
            regenerateSpec()
        } catch let e as CSVParser.ParseError {
            switch e {
            case .unterminatedQuote(let l):
                parseError = "Unterminated quote at line \(l)"
            }
        } catch {
            parseError = String(describing: error)
        }
    }

    private func regenerateSpec() {
        let trimmedName = newTableName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !csvHeader.isEmpty else {
            inferred = nil
            return
        }
        let sample = Array(csvAllRows.prefix(200))
        do {
            inferred = try CSVTableInferrer.infer(
                database: database, table: trimmedName,
                headers: csvHeader, rows: sample
            )
            editedTypes.removeAll()
            editedNullable.removeAll()
        } catch {
            inferred = nil
            parseError = String(describing: error)
        }
    }

    private func createAndImport() async {
        guard let spec = inferred,
              let client = env.activeClient else { return }
        working = true
        doneMessage = nil
        errorMessage = nil
        defer { working = false }

        // 1. CREATE TABLE
        let createSQL = effectiveCreateSQL(spec: spec)
        do {
            _ = try await client.exec(createSQL)
        } catch {
            errorMessage = String(format: NSLocalizedString(
                "csvNew.failedCreate", bundle: .module, comment: ""
            ), String(describing: error))
            return
        }

        // 2. 流式 INSERT（每批 500 行）
        importTotal = csvAllRows.count
        importProgress = 0
        let qualified = (try? SQLIdentifier.qualified(database: database, table: newTableName)) ?? newTableName
        let qCols = spec.columns
            .map { (try? SQLIdentifier.quote($0.cleanName)) ?? $0.cleanName }
            .joined(separator: ", ")
        let batchSize = 500
        var batch: [[String]] = []
        do {
            _ = try await client.exec("START TRANSACTION")
            for row in csvAllRows {
                batch.append(row)
                if batch.count >= batchSize {
                    try await flush(client: client, qualified: qualified,
                                     qCols: qCols, spec: spec, rows: batch)
                    importProgress += batch.count
                    batch.removeAll(keepingCapacity: true)
                }
            }
            if !batch.isEmpty {
                try await flush(client: client, qualified: qualified,
                                 qCols: qCols, spec: spec, rows: batch)
                importProgress += batch.count
            }
            _ = try await client.exec("COMMIT")
            doneMessage = String(format: NSLocalizedString(
                "csvNew.success", bundle: .module, comment: ""
            ), totalRows)
            // 刷新侧栏让新表立即出现
            await env.expandDatabase(database)
            // 1.2 秒后自动关掉，让用户看到 ✅ 提示
            try? await Task.sleep(for: .milliseconds(1200))
            onDone()
        } catch {
            _ = try? await client.exec("ROLLBACK")
            errorMessage = String(format: NSLocalizedString(
                "csvNew.failedImport", bundle: .module, comment: ""
            ), String(describing: error))
        }
    }

    private func flush(client: any DBClient,
                       qualified: String, qCols: String,
                       spec: CSVTableInferrer.Spec,
                       rows: [[String]]) async throws {
        var blocks: [String] = []
        for row in rows {
            var vals: [String] = []
            for (idx, col) in spec.columns.enumerated() {
                let raw = idx < row.count ? row[idx] : ""
                let nullable = editedNullable[col.cleanName] ?? col.nullable
                if raw.isEmpty && nullable {
                    vals.append("NULL")
                } else {
                    // 都按字符串字面量交给 server 处理类型转换
                    let escaped = raw.replacingOccurrences(of: "'", with: "''")
                    vals.append("'\(escaped)'")
                }
            }
            blocks.append("(\(vals.joined(separator: ", ")))")
        }
        let sql = "INSERT INTO \(qualified) (\(qCols)) VALUES \(blocks.joined(separator: ", "))"
        _ = try await client.exec(sql)
    }
}
