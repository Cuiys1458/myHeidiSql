import SwiftUI
import AppKit
import MacHeidiCore

/// 表结构编辑 Sheet（PRD §11 v0.3 DDL UI）。
///
/// 一次执行一个 ALTER TABLE 操作：添加列 / 删除列 / 修改列 / 重命名。
/// 多个改动 → 多次点 Apply（HeidiSQL 一次只发一条 ALTER）。
struct EditTableSchemaView: View {
    @Environment(AppEnvironment.self) private var env
    let database: String
    let table: String
    @Binding var isPresented: Bool
    let onDone: () -> Void   // 成功后回调（让 caller 刷新）

    @State private var schema: TableSchema?
    @State private var loading = true
    @State private var actionError: String?

    @State private var pendingSQL: String?          // 预览 SQL
    @State private var pendingWarnings: [String] = []
    @State private var executing: Bool = false

    @State private var draftMode: Mode = .none
    @State private var draftSpec: ColumnSpec = .blank()
    @State private var draftOldName: String = ""
    @State private var draftPosition: AlterColumnOperation.Position?

    // Index 编辑草稿
    @State private var idxDraftMode: IndexMode = .none
    @State private var idxName: String = ""
    @State private var idxColumns: Set<String> = []
    @State private var idxUnique: Bool = false

    enum Mode: Equatable { case none, add, modify, rename }
    enum IndexMode: Equatable { case none, add }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let schema {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        existingSection(schema)
                        editorSection(schema)
                        indexesSection(schema)
                        indexEditorSection(schema)
                        if let sql = pendingSQL {
                            previewSection(sql)
                        }
                    }
                    .padding(16)
                }
            } else if let err = actionError {
                Text(err).foregroundStyle(.red).padding()
            }
            Divider()
            footer
        }
        .frame(minWidth: 1100, idealWidth: 1200, minHeight: 640, idealHeight: 720)
        .task { await load() }
    }

    // MARK: header / footer

    @ViewBuilder
    private var header: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver.fill")
            Text("Edit Structure → `\(database)`.`\(table)`")
                .font(.headline.monospaced())
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if let err = actionError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
                    .lineLimit(1).help(err)
            }
            Spacer()
            Button("Close") { isPresented = false }
                .keyboardShortcut(.cancelAction)
                .disabled(executing)
            if pendingSQL != nil {
                Button("Apply") { Task { await execute() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(executing)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: sections

    @ViewBuilder
    private func existingSection(_ s: TableSchema) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Columns").font(.headline)
                Text("(\(s.columns.count))").foregroundStyle(.secondary)
                Spacer()
                Button {
                    draftMode = .add
                    draftSpec = .blank()
                    draftPosition = nil
                    pendingSQL = nil
                } label: {
                    Label("Add Column", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        th("Name", w: 220)
                        th("Type", w: 200)
                        th("Null", w: 60)
                        th("Default", w: 140)
                        th("Extra", w: 140)
                        th("Actions", w: 220)
                    }
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    Divider()
                    ForEach(Array(s.columns.enumerated()), id: \.offset) { idx, c in
                        HStack(spacing: 0) {
                            HStack(spacing: 4) {
                                if s.primaryKey.contains(c.name) {
                                    Image(systemName: "key.fill")
                                        .foregroundStyle(.yellow).font(.caption2)
                                }
                                Text(c.name).font(.callout.monospaced())
                                if !c.nullable {
                                    Text("*").foregroundStyle(.red).font(.caption2)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: 220, alignment: .leading)
                            .padding(.horizontal, 8)
                            Text(c.mysqlType).font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 200, alignment: .leading)
                                .padding(.horizontal, 8)
                                .lineLimit(1)
                            Text(c.nullable ? "YES" : "NO").font(.caption)
                                .frame(width: 60, alignment: .leading)
                                .padding(.horizontal, 8)
                            Text("").frame(width: 140).padding(.horizontal, 8)
                            Text(c.isAutoIncrement ? "auto_increment" : "")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 140, alignment: .leading)
                                .padding(.horizontal, 8)
                            HStack(spacing: 4) {
                                Button("Modify") { startModify(c) }
                                    .controlSize(.mini)
                                Button("Rename") { startRename(c) }
                                    .controlSize(.mini)
                                Button("Drop", role: .destructive) {
                                    generateDrop(name: c.name)
                                }
                                .controlSize(.mini)
                            }
                            .frame(width: 220, alignment: .leading)
                            .padding(.horizontal, 8)
                        }
                        .padding(.vertical, 3)
                        .background(idx % 2 != 0 ? Color.primary.opacity(0.04) : Color.clear)
                    }
                }
                .frame(minWidth: 220 + 200 + 60 + 140 + 140 + 220)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    @ViewBuilder
    private func editorSection(_ s: TableSchema) -> some View {
        if draftMode != .none {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(editorTitle).font(.headline)
                    Spacer()
                    Button("Cancel") { draftMode = .none; pendingSQL = nil }
                        .controlSize(.small)
                }
                Form {
                    if draftMode == .rename {
                        LabeledContent("Old Name") {
                            Text(draftOldName).foregroundStyle(.secondary)
                        }
                    }
                    TextField("Column Name", text: $draftSpec.name)
                    TextField("Type (e.g. INT, VARCHAR(100), BIGINT UNSIGNED)",
                              text: $draftSpec.mysqlType)
                    Toggle("Nullable", isOn: $draftSpec.nullable)
                    TextField("Default literal (optional, e.g. 0, 'active', NULL)",
                              text: Binding(
                                get: { draftSpec.defaultLiteral ?? "" },
                                set: { draftSpec.defaultLiteral = $0.isEmpty ? nil : $0 }
                              ))
                    Toggle("AUTO_INCREMENT", isOn: $draftSpec.isAutoIncrement)
                    if draftMode == .add {
                        Toggle("Set as PRIMARY KEY", isOn: $draftSpec.isPrimaryKey)
                        Picker("Position", selection: positionBinding(in: s)) {
                            Text("(end of table)").tag(Optional<AlterColumnOperation.Position>.none)
                            Text("FIRST").tag(Optional.some(AlterColumnOperation.Position.first))
                            ForEach(s.columns, id: \.name) { col in
                                Text("AFTER \(col.name)")
                                    .tag(Optional.some(AlterColumnOperation.Position.after(col.name)))
                            }
                        }
                    }
                    TextField("Comment (optional)",
                              text: Binding(
                                get: { draftSpec.comment ?? "" },
                                set: { draftSpec.comment = $0.isEmpty ? nil : $0 }
                              ))
                }
                .formStyle(.grouped)
                Button {
                    generateFromDraft()
                } label: {
                    Label("Generate SQL", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftSpec.name.isEmpty || draftSpec.mysqlType.isEmpty)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.06))
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func indexesSection(_ s: TableSchema) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Indexes").font(.headline)
                Text("(\(s.indices.count))").foregroundStyle(.secondary)
                Spacer()
                Button {
                    idxDraftMode = .add
                    idxName = ""
                    idxColumns = []
                    idxUnique = false
                    pendingSQL = nil
                } label: {
                    Label("Add Index", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            if s.indices.isEmpty {
                Text("No indexes defined.")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        th("Name", w: 240)
                        th("Columns", w: 320)
                        th("Type", w: 100)
                        th("Actions", w: 120)
                    }
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    Divider()
                    ForEach(Array(s.indices.enumerated()), id: \.offset) { idx, m in
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
                            .frame(width: 240, alignment: .leading)
                            .padding(.horizontal, 8)
                            Text(m.columns.joined(separator: ", "))
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                .frame(width: 320, alignment: .leading)
                                .padding(.horizontal, 8).lineLimit(1)
                            Text(m.name == "PRIMARY" ? "PRIMARY"
                                    : (m.unique ? "UNIQUE" : "INDEX"))
                                .font(.caption)
                                .frame(width: 100, alignment: .leading)
                                .padding(.horizontal, 8)
                            Button("Drop", role: .destructive) {
                                dropIndex(name: m.name)
                            }
                            .controlSize(.mini)
                            .frame(width: 120, alignment: .leading)
                            .padding(.horizontal, 8)
                        }
                        .padding(.vertical, 3)
                        .background(idx % 2 != 0 ? Color.primary.opacity(0.04) : Color.clear)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }

    @ViewBuilder
    private func indexEditorSection(_ s: TableSchema) -> some View {
        if idxDraftMode == .add {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Add Index").font(.headline)
                    Spacer()
                    Button("Cancel") { idxDraftMode = .none; pendingSQL = nil }
                        .controlSize(.small)
                }
                Form {
                    TextField("Index Name (e.g. idx_email)", text: $idxName)
                    Toggle("UNIQUE", isOn: $idxUnique)
                    LabeledContent("Columns") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(s.columns, id: \.name) { col in
                                Toggle(isOn: idxColBinding(col.name)) {
                                    HStack(spacing: 4) {
                                        Text(col.name).font(.callout.monospaced())
                                        Text(col.mysqlType).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                Button {
                    generateAddIndex(schema: s)
                } label: {
                    Label("Generate SQL", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(idxName.isEmpty || idxColumns.isEmpty)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.06))
            .cornerRadius(6)
        }
    }

    private func idxColBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { idxColumns.contains(name) },
            set: { isOn in
                if isOn { idxColumns.insert(name) } else { idxColumns.remove(name) }
            }
        )
    }

    private func generateAddIndex(schema: TableSchema) {
        // 保留 schema.columns 顺序，让生成的索引按表自然顺序
        let ordered = schema.columns.map(\.name).filter { idxColumns.contains($0) }
        do {
            let sql = try DDLGenerator.addIndex(
                database: database, table: table,
                indexName: idxName, columns: ordered, unique: idxUnique
            )
            pendingSQL = sql
            pendingWarnings = []
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    private func dropIndex(name: String) {
        do {
            let sql = try DDLGenerator.dropIndex(
                database: database, table: table, indexName: name
            )
            pendingSQL = sql
            pendingWarnings = []
            idxDraftMode = .none
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    @ViewBuilder
    private func previewSection(_ sql: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SQL Preview").font(.headline)
            ScrollView {
                Text(sql)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
            if !pendingWarnings.isEmpty {
                ForEach(Array(pendingWarnings.enumerated()), id: \.offset) { _, w in
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                }
            }
        }
    }

    // MARK: header helper

    @ViewBuilder
    private func th(_ s: String, w: CGFloat) -> some View {
        Text(s).font(.caption.bold()).foregroundStyle(.secondary)
            .frame(width: w, alignment: .leading)
            .padding(.horizontal, 8)
    }

    // MARK: state helpers

    private var editorTitle: String {
        switch draftMode {
        case .add:    return "Add Column"
        case .modify: return "Modify Column"
        case .rename: return "Rename Column"
        case .none:   return ""
        }
    }

    private func positionBinding(in s: TableSchema) -> Binding<AlterColumnOperation.Position?> {
        Binding(
            get: { draftPosition },
            set: { draftPosition = $0 }
        )
    }

    private func startModify(_ c: ColumnMeta) {
        draftMode = .modify
        draftSpec = ColumnSpec(
            name: c.name, mysqlType: c.mysqlType,
            nullable: c.nullable, defaultLiteral: nil,
            isAutoIncrement: c.isAutoIncrement
        )
        draftOldName = c.name
        pendingSQL = nil
    }

    private func startRename(_ c: ColumnMeta) {
        draftMode = .rename
        draftOldName = c.name
        draftSpec = ColumnSpec(
            name: c.name, mysqlType: c.mysqlType,
            nullable: c.nullable, defaultLiteral: nil,
            isAutoIncrement: c.isAutoIncrement
        )
        pendingSQL = nil
    }

    // MARK: SQL generation

    private func generateFromDraft() {
        guard let s = schema else { return }
        do {
            let op: AlterColumnOperation
            switch draftMode {
            case .add:    op = .add(column: draftSpec, position: draftPosition)
            case .modify: op = .modify(name: draftOldName, newSpec: draftSpec)
            case .rename: op = .rename(oldName: draftOldName, newSpec: draftSpec)
            case .none:   return
            }
            let r = try DDLGenerator.alter(
                database: database, table: table,
                currentColumns: s.columns, currentPrimaryKey: s.primaryKey,
                operation: op
            )
            pendingSQL = r.sql
            pendingWarnings = r.warnings
            actionError = nil
        } catch {
            actionError = String(describing: error)
            pendingSQL = nil
        }
    }

    private func generateDrop(name: String) {
        guard let s = schema else { return }
        do {
            let r = try DDLGenerator.alter(
                database: database, table: table,
                currentColumns: s.columns, currentPrimaryKey: s.primaryKey,
                operation: .drop(name: name)
            )
            pendingSQL = r.sql
            pendingWarnings = r.warnings
            draftMode = .none
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    // MARK: load + execute

    private func load() async {
        loading = true
        defer { loading = false }
        schema = await env.loadTableSchema(database: database, table: table)
    }

    private func execute() async {
        guard let sql = pendingSQL, let client = env.activeClient else { return }
        executing = true
        defer { executing = false }
        do {
            _ = try await client.exec(sql)
            pendingSQL = nil
            pendingWarnings = []
            draftMode = .none
            actionError = nil
            // 重新加载 schema 给下一次操作
            await load()
            onDone()
        } catch let e as DBError {
            actionError = describeDB(e)
        } catch {
            actionError = String(describing: error)
        }
    }

    private func describeDB(_ e: DBError) -> String {
        switch e {
        case .syntax(let n, _, let m): return "ERROR \(n): \(m)"
        case .auth(let m, _): return "AUTH: \(m)"
        case .server(let n, _, let m): return "SERVER \(n): \(m)"
        default: return String(describing: e)
        }
    }
}

private extension ColumnSpec {
    static func blank() -> ColumnSpec {
        ColumnSpec(name: "", mysqlType: "VARCHAR(100)")
    }
}
