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

    // Foreign Key 编辑草稿
    @State private var fks: [AppEnvironment.ForeignKeyEntry] = []
    @State private var fkDraftMode: FKMode = .none
    @State private var fkName: String = ""
    @State private var fkColumns: Set<String> = []
    @State private var fkRefDatabase: String = ""
    @State private var fkRefTable: String = ""
    @State private var fkRefColumns: String = ""
    @State private var fkOnDelete: DDLGenerator.ForeignKeySpec.ReferentialAction = .noAction
    @State private var fkOnUpdate: DDLGenerator.ForeignKeySpec.ReferentialAction = .noAction

    // Table Options 编辑草稿
    @State private var optDraftOpen: Bool = false
    @State private var optEngine: String = ""
    @State private var optCharset: String = ""
    @State private var optCollation: String = ""
    @State private var optComment: String = ""
    @State private var optNewName: String = ""

    enum Mode: Equatable { case none, add, modify, rename }
    enum IndexMode: Equatable { case none, add }
    enum FKMode: Equatable { case none, add }

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
                        foreignKeysSection(schema)
                        fkEditorSection(schema)
                        tableOptionsSection(schema)
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
            Text(String(format: NSLocalizedString(
                "ddl.title", bundle: .module, comment: ""
            ), database, table))
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
            Button(L("ddl.close")) { isPresented = false }
                .keyboardShortcut(.cancelAction)
                .disabled(executing)
            if pendingSQL != nil {
                Button(L("ddl.apply")) { Task { await execute() } }
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
                Text(L("ddl.columns")).font(.headline)
                Text("(\(s.columns.count))").foregroundStyle(.secondary)
                Spacer()
                Button {
                    draftMode = .add
                    draftSpec = .blank()
                    draftPosition = nil
                    pendingSQL = nil
                } label: {
                    Label(L("ddl.addColumn"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        thL("ddl.colName", w: 220)
                        thL("ddl.colType", w: 200)
                        thL("ddl.colNull", w: 60)
                        thL("ddl.colDefault", w: 140)
                        thL("ddl.colExtra", w: 140)
                        thL("ddl.actions", w: 220)
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
                                Button(L("ddl.modify")) { startModify(c) }
                                    .controlSize(.mini)
                                Button(L("ddl.rename")) { startRename(c) }
                                    .controlSize(.mini)
                                Button(L("ddl.drop"), role: .destructive) {
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
                    Button(L("ddl.cancel")) { draftMode = .none; pendingSQL = nil }
                        .controlSize(.small)
                }
                Form {
                    if draftMode == .rename {
                        LabeledContent {
                            Text(draftOldName).foregroundStyle(.secondary)
                        } label: {
                            Text(L("ddl.colName"))
                        }
                    }
                    TextField("", text: $draftSpec.name,
                              prompt: Text(L("ddl.colName")))
                    TextField("", text: $draftSpec.mysqlType,
                              prompt: Text(L("ddl.colType")))
                    Toggle(L("ddl.colNullable"), isOn: $draftSpec.nullable)
                    TextField("", text: Binding(
                                get: { draftSpec.defaultLiteral ?? "" },
                                set: { draftSpec.defaultLiteral = $0.isEmpty ? nil : $0 }
                              ),
                              prompt: Text(L("ddl.colDefault")))
                    Toggle(L("ddl.colAuto"), isOn: $draftSpec.isAutoIncrement)
                    if draftMode == .add {
                        Toggle(L("ddl.colPK"), isOn: $draftSpec.isPrimaryKey)
                        Picker(selection: positionBinding(in: s)) {
                            Text(L("ddl.posNone")).tag(Optional<AlterColumnOperation.Position>.none)
                            Text(L("ddl.posFirst")).tag(Optional.some(AlterColumnOperation.Position.first))
                            ForEach(s.columns, id: \.name) { col in
                                Text(verbatim: "AFTER \(col.name)")
                                    .tag(Optional.some(AlterColumnOperation.Position.after(col.name)))
                            }
                        } label: {
                            Text(L("ddl.position"))
                        }
                    }
                    TextField("", text: Binding(
                                get: { draftSpec.comment ?? "" },
                                set: { draftSpec.comment = $0.isEmpty ? nil : $0 }
                              ),
                              prompt: Text(L("ddl.colComment")))
                }
                .formStyle(.grouped)
                Button {
                    generateFromDraft()
                } label: {
                    Label(L("ddl.generateSQL"), systemImage: "wand.and.stars")
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
                Text(L("ddl.indexes")).font(.headline)
                Text("(\(s.indices.count))").foregroundStyle(.secondary)
                Spacer()
                Button {
                    idxDraftMode = .add
                    idxName = ""
                    idxColumns = []
                    idxUnique = false
                    pendingSQL = nil
                } label: {
                    Label(L("ddl.addIndex"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            if s.indices.isEmpty {
                Text(L("ddl.idx.empty"))
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        thL("ddl.idxName", w: 240)
                        thL("ddl.idxColumns", w: 320)
                        thL("ddl.idx.type", w: 100)
                        thL("ddl.actions", w: 120)
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
                            Button(L("ddl.drop"), role: .destructive) {
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
                    Text(L("ddl.addIndex")).font(.headline)
                    Spacer()
                    Button(L("ddl.cancel")) { idxDraftMode = .none; pendingSQL = nil }
                        .controlSize(.small)
                }
                Form {
                    TextField("", text: $idxName, prompt: Text(L("ddl.idxName")))
                    Toggle(L("ddl.idxUnique"), isOn: $idxUnique)
                    LabeledContent {
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
                    } label: {
                        Text(L("ddl.idxColumns"))
                    }
                }
                .formStyle(.grouped)
                Button {
                    generateAddIndex(schema: s)
                } label: {
                    Label(L("ddl.generateSQL"), systemImage: "wand.and.stars")
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

    // MARK: Foreign Keys section

    @ViewBuilder
    private func foreignKeysSection(_ s: TableSchema) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("ddl.foreignKeys")).font(.headline)
                Text("(\(fks.count))").foregroundStyle(.secondary)
                Spacer()
                Button {
                    fkDraftMode = .add
                    fkName = ""
                    fkColumns = []
                    fkRefDatabase = ""
                    fkRefTable = ""
                    fkRefColumns = ""
                    fkOnDelete = .noAction
                    fkOnUpdate = .noAction
                    pendingSQL = nil
                } label: {
                    Label(L("ddl.addForeignKey"), systemImage: "link.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            if fks.isEmpty {
                Text(L("ddl.fk.empty"))
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        thL("ddl.fk.constraint", w: 200)
                        thL("bulk.column", w: 160)
                        thL("ddl.fk.references", w: 320)
                        thL("ddl.actions", w: 120)
                    }
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    Divider()
                    // group by constraint name → 复合 FK 多列归一
                    let grouped = Dictionary(grouping: fks, by: { $0.constraint })
                    let names = grouped.keys.sorted()
                    ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                        let entries = grouped[name] ?? []
                        let cols = entries.map(\.column).joined(separator: ", ")
                        let refDb = entries.first?.refDatabase ?? ""
                        let refTb = entries.first?.refTable ?? ""
                        let refCols = entries.map(\.refColumn).joined(separator: ", ")
                        let refLabel = refDb.isEmpty
                            ? "`\(refTb)` (\(refCols))"
                            : "`\(refDb)`.`\(refTb)` (\(refCols))"
                        HStack(spacing: 0) {
                            HStack(spacing: 4) {
                                Image(systemName: "link").foregroundStyle(.green).font(.caption2)
                                Text(name).font(.callout.monospaced()).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(width: 200, alignment: .leading)
                            .padding(.horizontal, 8)
                            Text(cols)
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                .frame(width: 160, alignment: .leading)
                                .padding(.horizontal, 8).lineLimit(1)
                            Text(refLabel)
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                .frame(width: 320, alignment: .leading)
                                .padding(.horizontal, 8).lineLimit(1)
                            Button(L("ddl.drop"), role: .destructive) {
                                dropForeignKey(name: name)
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
    private func fkEditorSection(_ s: TableSchema) -> some View {
        if fkDraftMode == .add {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("ddl.addForeignKey")).font(.headline)
                    Spacer()
                    Button(L("ddl.cancel")) { fkDraftMode = .none; pendingSQL = nil }
                        .controlSize(.small)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text(L("ddl.fk.constraint")).font(.caption)
                        TextField("", text: $fkName,
                                  prompt: Text(verbatim: "fk_<table>_<col>"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    GridRow {
                        Text(L("ddl.fk.localCols")).font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(s.columns, id: \.name) { c in
                                Toggle(isOn: Binding(
                                    get: { fkColumns.contains(c.name) },
                                    set: { v in
                                        if v { fkColumns.insert(c.name) }
                                        else { fkColumns.remove(c.name) }
                                    }
                                )) {
                                    Text(c.name).font(.callout.monospaced())
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    GridRow {
                        Text(L("ddl.fk.refDatabase")).font(.caption)
                        TextField("", text: $fkRefDatabase,
                                  prompt: Text(L("ddl.fk.refDatabasePh")))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    GridRow {
                        Text(L("ddl.fk.refTable")).font(.caption)
                        TextField("", text: $fkRefTable,
                                  prompt: Text(verbatim: "users"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    GridRow {
                        Text(L("ddl.fk.refColumns")).font(.caption)
                        TextField("", text: $fkRefColumns,
                                  prompt: Text(L("ddl.fk.refColumnsPh")))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    GridRow {
                        Text(L("ddl.fk.onDelete")).font(.caption)
                        Picker("", selection: $fkOnDelete) {
                            ForEach(DDLGenerator.ForeignKeySpec.ReferentialAction.allCases,
                                    id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                    GridRow {
                        Text(L("ddl.fk.onUpdate")).font(.caption)
                        Picker("", selection: $fkOnUpdate) {
                            ForEach(DDLGenerator.ForeignKeySpec.ReferentialAction.allCases,
                                    id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                }
                Button {
                    addForeignKey()
                } label: {
                    Label(L("ddl.generateSQL"), systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func addForeignKey() {
        do {
            let cols = Array(fkColumns).sorted()
            let refCols = fkRefColumns
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let spec = DDLGenerator.ForeignKeySpec(
                name: fkName,
                columns: cols,
                refDatabase: fkRefDatabase.isEmpty ? nil : fkRefDatabase,
                refTable: fkRefTable,
                refColumns: refCols,
                onDelete: fkOnDelete,
                onUpdate: fkOnUpdate
            )
            let sql = try DDLGenerator.addForeignKey(
                database: database, table: table, fk: spec
            )
            pendingSQL = sql
            pendingWarnings = []
            fkDraftMode = .none
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    private func dropForeignKey(name: String) {
        do {
            let sql = try DDLGenerator.dropForeignKey(
                database: database, table: table, name: name
            )
            pendingSQL = sql
            pendingWarnings = []
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    // MARK: Table Options section

    @ViewBuilder
    private func tableOptionsSection(_ s: TableSchema) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("ddl.tableOptions")).font(.headline)
                Spacer()
                Button {
                    optDraftOpen.toggle()
                    if optDraftOpen {
                        optEngine = ""
                        optCharset = ""
                        optCollation = ""
                        optComment = ""
                        optNewName = ""
                        pendingSQL = nil
                    }
                } label: {
                    Label(optDraftOpen ? L("ddl.hideOptions") : L("ddl.editOptions"),
                          systemImage: optDraftOpen ? "chevron.up" : "slider.horizontal.3")
                }
                .controlSize(.small)
            }
            if optDraftOpen {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text(L("ddl.opts.engine")).font(.caption)
                        TextField("", text: $optEngine,
                                  prompt: Text(verbatim: "InnoDB / MyISAM"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }
                    GridRow {
                        Text(L("ddl.opts.charset")).font(.caption)
                        TextField("", text: $optCharset,
                                  prompt: Text(verbatim: "utf8mb4"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }
                    GridRow {
                        Text(L("ddl.opts.collation")).font(.caption)
                        TextField("", text: $optCollation,
                                  prompt: Text(verbatim: "utf8mb4_general_ci"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }
                    GridRow {
                        Text(L("ddl.opts.comment")).font(.caption)
                        TextField("", text: $optComment,
                                  prompt: Text(L("ddl.opts.commentPh")))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 480)
                    }
                    GridRow {
                        Text(L("ddl.opts.rename")).font(.caption)
                        TextField("", text: $optNewName,
                                  prompt: Text(L("ddl.opts.renamePh")))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }
                }
                HStack {
                    Button {
                        applyTableOptions()
                    } label: {
                        Label(L("ddl.generateSQL"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Text(L("ddl.opts.hint"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func applyTableOptions() {
        do {
            // 优先 RENAME（独立语句）
            if !optNewName.trimmingCharacters(in: .whitespaces).isEmpty {
                let sql = try DDLGenerator.renameTable(
                    database: database, table: table, newName: optNewName
                )
                pendingSQL = sql
                pendingWarnings = []
                actionError = nil
                return
            }
            let sql = try DDLGenerator.setTableOptions(
                database: database, table: table,
                engine: optEngine.isEmpty ? nil : optEngine,
                charset: optCharset.isEmpty ? nil : optCharset,
                collation: optCollation.isEmpty ? nil : optCollation,
                comment: optComment.isEmpty ? nil : optComment
            )
            guard let sql else {
                actionError = LS("ddl.opts.fillFirst")
                return
            }
            pendingSQL = sql
            pendingWarnings = []
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    @ViewBuilder
    private func previewSection(_ sql: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("ddl.preview")).font(.headline)
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

    /// 同 th，但字符串走 i18n。
    @ViewBuilder
    private func thL(_ key: String, w: CGFloat) -> some View {
        Text(LS(key)).font(.caption.bold()).foregroundStyle(.secondary)
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
        fks = await env.loadForeignKeys(database: database, table: table)
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
