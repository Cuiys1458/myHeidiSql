import SwiftUI
import AppKit
import MacHeidiCore

/// 单击表节点显示的元信息视图（PRD §5.2.3 / §6.3）。
///
/// 拉 SHOW TABLE STATUS + SHOW FULL COLUMNS，只读展示。
struct TableInfoView: View {
    @Environment(AppEnvironment.self) private var env
    let database: String
    let table: String

    @State private var status: TableStatus?
    @State private var schema: TableSchema?
    @State private var foreignKeys: [AppEnvironment.ForeignKeyEntry] = []
    @State private var createDDL: String?
    @State private var error: String?
    @State private var loading = true
    @State private var showEditSchema = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("`\(database)`.`\(table)`")
                    .font(.headline.monospaced())
                Spacer()
                Button {
                    showEditSchema = true
                } label: {
                    Label(L("info.editStructure"), systemImage: "wrench.and.screwdriver")
                }
                Button {
                    Task { await load() }
                } label: {
                    Label(L("info.refresh"), systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(8)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                ScrollView {
                    Text(err).foregroundStyle(.red)
                        .font(.system(.body, design: .monospaced))
                        .padding().textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let s = status { statusSection(s) }
                        if let sc = schema, !sc.columns.isEmpty {
                            columnsSection(sc)
                        }
                        if let sc = schema, !sc.indices.isEmpty {
                            indicesSection(sc.indices)
                        }
                        if !foreignKeys.isEmpty {
                            foreignKeysSection(foreignKeys)
                        }
                        if let ddl = createDDL { ddlSection(ddl) }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showEditSchema) {
            EditTableSchemaView(
                database: database, table: table,
                isPresented: $showEditSchema,
                onDone: { Task { await load() } }
            )
            .environment(env)
        }
    }

    @ViewBuilder
    private func statusSection(_ s: TableStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("info.status")).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                statusRow("Engine", s.engine)
                statusRow("Rows (estimate)", s.rows.map(String.init) ?? "?")
                statusRow("Avg Row Length", s.avgRowLength.map(String.init) ?? "?")
                statusRow("Data Length", formatBytes(s.dataLength))
                statusRow("Index Length", formatBytes(s.indexLength))
                statusRow("Collation", s.collation)
                statusRow("Created", s.createTime)
                statusRow("Updated", s.updateTime)
                statusRow("Comment", s.comment)
            }
        }
    }

    @ViewBuilder
    private func columnsSection(_ s: TableSchema) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("info.columns")).font(.headline)
                Text("(\(s.columns.count))").foregroundStyle(.secondary)
                if !s.primaryKey.isEmpty {
                    Image(systemName: "key.fill").foregroundStyle(.yellow)
                    Text("PK: \(s.primaryKey.joined(separator: ", "))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    columnHeader("Name", width: 180)
                    columnHeader("Type", width: 200)
                    columnHeader("Null", width: 60)
                    columnHeader("Key", width: 60)
                    columnHeader("Extra", width: 160)
                    columnHeader("Comment", width: 240)
                }
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                Divider()
                ForEach(Array(s.columns.enumerated()), id: \.offset) { idx, c in
                    HStack(spacing: 0) {
                        columnCell(c.name, width: 180, isMono: true,
                                    pk: s.primaryKey.contains(c.name))
                        columnCell(c.mysqlType, width: 200, isMono: true)
                        columnCell(c.nullable ? "YES" : "NO", width: 60)
                        columnCell(s.primaryKey.contains(c.name) ? "PRI" : "", width: 60)
                        columnCell(c.isAutoIncrement ? "auto_increment" : "", width: 160)
                        columnCell(c.comment, width: 240)
                    }
                    .padding(.vertical, 3)
                    .background(idx % 2 != 0 ? Color.primary.opacity(0.04) : Color.clear)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    @ViewBuilder
    private func indicesSection(_ idx: [IndexMeta]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("info.indexes")).font(.headline)
                Text("(\(idx.count))").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    columnHeader("Name", width: 220)
                    columnHeader("Columns", width: 320)
                    columnHeader("Unique", width: 80)
                    columnHeader("Type", width: 100)
                }
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                Divider()
                ForEach(Array(idx.enumerated()), id: \.offset) { i, m in
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            if m.name == "PRIMARY" {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(.yellow).font(.caption2)
                            } else if m.unique {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.blue).font(.caption2)
                            }
                            Text(m.name).font(.callout.monospaced()).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 220, alignment: .leading)
                        .padding(.horizontal, 8)
                        columnCell(m.columns.joined(separator: ", "), width: 320, isMono: true)
                        columnCell(m.unique ? "YES" : "NO", width: 80)
                        columnCell(m.name == "PRIMARY" ? "PRIMARY" : (m.unique ? "UNIQUE" : "INDEX"),
                                    width: 100)
                    }
                    .padding(.vertical, 3)
                    .background(i % 2 != 0 ? Color.primary.opacity(0.04) : Color.clear)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    @ViewBuilder
    private func foreignKeysSection(_ fks: [AppEnvironment.ForeignKeyEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("info.foreignKeys")).font(.headline)
                Text("(\(fks.count))").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    columnHeader("Constraint", width: 240)
                    columnHeader("Column", width: 160)
                    columnHeader("→", width: 30)
                    columnHeader("References", width: 320)
                }
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                Divider()
                ForEach(Array(fks.enumerated()), id: \.offset) { i, fk in
                    HStack(spacing: 0) {
                        columnCell(fk.constraint, width: 240, isMono: true)
                        columnCell(fk.column, width: 160, isMono: true)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary).font(.caption)
                            .frame(width: 30)
                        let target = fk.refDatabase.isEmpty
                            ? "\(fk.refTable).\(fk.refColumn)"
                            : "\(fk.refDatabase).\(fk.refTable).\(fk.refColumn)"
                        columnCell(target, width: 320, isMono: true)
                    }
                    .padding(.vertical, 3)
                    .background(i % 2 != 0 ? Color.primary.opacity(0.04) : Color.clear)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    @ViewBuilder
    private func ddlSection(_ ddl: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("info.ddl")).font(.headline)
                Spacer()
                Button(L("info.copy")) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(ddl, forType: .string)
                }
                .controlSize(.small)
            }
            ScrollView {
                Text(ddl)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
        }
    }

    @ViewBuilder
    private func statusRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).font(.callout)
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
        }
    }
    @ViewBuilder
    private func columnHeader(_ s: String, width: CGFloat) -> some View {
        Text(s)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
    }
    @ViewBuilder
    private func columnCell(_ s: String, width: CGFloat,
                              isMono: Bool = false, pk: Bool = false) -> some View {
        HStack(spacing: 4) {
            if pk {
                Image(systemName: "key.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption2)
            }
            Text(s)
                .font(isMono ? .system(.callout, design: .monospaced) : .callout)
                .lineLimit(1).truncationMode(.tail)
                .help(s)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func formatBytes(_ n: UInt64?) -> String {
        guard let v = n else { return "?" }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .binary
        return f.string(fromByteCount: Int64(v))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        guard let client = env.activeClient else { return }
        let qualified: String
        do { qualified = try SQLIdentifier.qualified(database: database, table: table) }
        catch {
            self.error = "Invalid table name"
            return
        }
        // 1. SHOW TABLE STATUS LIKE '<table>'
        do {
            let safeTable = table.replacingOccurrences(of: "'", with: "''")
            let qDb = try SQLIdentifier.quote(database)
            let rs = try await client.query(
                "SHOW TABLE STATUS FROM \(qDb) LIKE '\(safeTable)'"
            )
            if let row = rs.rows.first {
                status = TableStatus.from(row: row, columns: rs.columns)
            }
            schema = await env.loadTableSchema(database: database, table: table)
            foreignKeys = await env.loadForeignKeys(database: database, table: table)
            // 拉 CREATE DDL（最佳努力；过程/函数/触发器可能 schema 是空，这里仍能展示）
            if let client = env.activeClient,
               let q = try? SQLIdentifier.qualified(database: database, table: table),
               let rs = try? await client.query("SHOW CREATE TABLE \(q)"),
               let row = rs.rows.first, row.count >= 2 {
                if case .string(let ddl) = row[1] { createDDL = ddl }
                else if case .blob(let d) = row[1] { createDDL = String(data: d, encoding: .utf8) }
            }
            error = nil
            _ = qualified
        } catch let e as DBError {
            error = describeError(e)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func describeError(_ e: DBError) -> String {
        switch e {
        case .syntax(let n, _, let m): return "ERROR \(n): \(m)"
        case .auth(let m, _):          return "AUTH: \(m)"
        case .network(let m, _):       return "NETWORK: \(m)"
        default:                        return String(describing: e)
        }
    }
}

private struct TableStatus {
    let engine: String
    let rows: UInt64?
    let avgRowLength: UInt64?
    let dataLength: UInt64?
    let indexLength: UInt64?
    let collation: String
    let createTime: String
    let updateTime: String
    let comment: String

    static func from(row: [CellValue], columns: [ColumnMeta]) -> TableStatus {
        func find(_ name: String) -> CellValue? {
            guard let i = columns.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                  i < row.count else { return nil }
            return row[i]
        }
        func string(_ name: String) -> String {
            switch find(name) {
            case .some(.string(let s)): return s
            case .some(.int(let v)): return String(v)
            case .some(.uint(let v)): return String(v)
            case .some(.blob(let d)): return String(data: d, encoding: .utf8) ?? ""
            case .some(.json(let s)): return s
            case .some(.null), .none: return ""
            default: return ""
            }
        }
        func uint(_ name: String) -> UInt64? {
            switch find(name) {
            case .some(.uint(let v)): return v
            case .some(.int(let v)) where v >= 0: return UInt64(v)
            case .some(.string(let s)): return UInt64(s)
            case .some(.blob(let d)):
                guard let s = String(data: d, encoding: .utf8) else { return nil }
                return UInt64(s)
            default: return nil
            }
        }
        return TableStatus(
            engine: string("Engine"),
            rows: uint("Rows"),
            avgRowLength: uint("Avg_row_length"),
            dataLength: uint("Data_length"),
            indexLength: uint("Index_length"),
            collation: string("Collation"),
            createTime: string("Create_time"),
            updateTime: string("Update_time"),
            comment: string("Comment")
        )
    }
}
