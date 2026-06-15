import SwiftUI
import AppKit
import MacHeidiCore

struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    let onEditSession: () -> Void

    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 搜索框（仅连接后显示）
            if env.activeSession != nil && env.connectionState == .connected {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("", text: $searchText, prompt: Text(L("sidebar.filterTables")))
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
            }

            List {
                Section(header: Text(L("sidebar.sessions"))) {
                    ForEach(env.sessions) { session in
                        SessionRow(session: session, onEditSession: onEditSession)
                    }
                }
                if env.activeSession != nil && env.connectionState == .connected {
                    if searchText.isEmpty {
                        // 正常模式：按数据库分组展开
                        Section(header: Text(L("sidebar.databases"))) {
                            ForEach(env.databases, id: \.self) { db in
                                DatabaseNode(name: db)
                            }
                        }
                    } else {
                        // 搜索模式：跨库扁平显示匹配项
                        Section("Search Results") {
                            let hits = filteredHits(query: searchText)
                            if hits.isEmpty {
                                Text(L("sidebar.noMatches"))
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            } else {
                                ForEach(hits, id: \.self) { hit in
                                    SearchHitRow(database: hit.db, table: hit.table)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .task(id: searchText) {
            // 搜索时如果某些库还没展开过，自动加载它们的表列表
            guard !searchText.isEmpty else { return }
            for db in env.databases where env.tablesByDb[db] == nil {
                await env.expandDatabase(db)
                env.collapseDatabase(db)   // 仅加载，不强制展开 UI
            }
        }
    }

    /// 跨库搜索：模糊匹配表名 / 视图 / 存储过程 / 函数 / 触发器名（大小写不敏感）。
    private func filteredHits(query: String) -> [SearchHit] {
        let q = query.lowercased()
        var out: [SearchHit] = []
        for db in env.databases {
            guard let tables = env.tablesByDb[db] else { continue }
            for t in tables where t.name.lowercased().contains(q) {
                out.append(SearchHit(db: db, table: t))
            }
        }
        // 按 db.table 排序
        return out.sorted {
            if $0.db != $1.db { return $0.db < $1.db }
            return $0.table.name < $1.table.name
        }
    }
}

private struct SearchHit: Hashable {
    let db: String
    let table: TableMeta

    static func == (lhs: SearchHit, rhs: SearchHit) -> Bool {
        lhs.db == rhs.db && lhs.table.name == rhs.table.name && lhs.table.kind == rhs.table.kind
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(db)
        hasher.combine(table.name)
        hasher.combine(table.kind)
    }
}

/// 搜索结果行（带 db.table 限定显示）。
private struct SearchHitRow: View {
    @Environment(AppEnvironment.self) private var env
    let database: String
    let table: TableMeta

    private var isSelected: Bool {
        switch env.selectedNode {
        case .table(let d, let t): return d == database && t == table.name && table.kind == .table
        case .view(let d, let v):  return d == database && v == table.name && table.kind == .view
        default: return false
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: table.kind))
                .foregroundStyle(isSelected ? Color.accentColor : iconColor(for: table.kind))
                .font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(table.name)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                Text(database)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            switch table.kind {
            case .table, .view:
                env.openDataTab(database: database, table: table.name)
            default:
                env.openTableInfoTab(database: database, table: table.name)
            }
            env.selectedNode = (table.kind == .view)
                ? .view(database: database, view: table.name)
                : .table(database: database, table: table.name)
        }
        .contextMenu {
            Button(L("menu.openData")) {
                env.openDataTab(database: database, table: table.name)
            }
            Button(L("menu.showTableInfo")) {
                env.openTableInfoTab(database: database, table: table.name)
            }
        }
    }

    private func iconName(for kind: TableKind) -> String {
        switch kind {
        case .table:     return "tablecells"
        case .view:      return "eye"
        case .procedure: return "function"
        case .function:  return "f.cursive"
        case .trigger:   return "bolt.circle"
        case .event:     return "calendar"
        }
    }
    private func iconColor(for kind: TableKind) -> Color {
        switch kind {
        case .table, .view:    return .secondary
        case .procedure, .function: return .purple
        case .trigger:         return .orange
        case .event:           return .blue
        }
    }
}

private struct SessionRow: View {
    @Environment(AppEnvironment.self) private var env
    let session: SessionConfig
    let onEditSession: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicator)
                .frame(width: 8, height: 8)
            Text(session.name)
                .lineLimit(1)
            Spacer()
            if isConnecting {
                ProgressView().controlSize(.mini)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            Task { await env.openSession(session) }
        }
        .contextMenu {
            Button(L("menu.openSession")) {
                Task { await env.openSession(session) }
            }
            Button(L("menu.editSession")) {
                onEditSession()
            }
            Button(L("menu.duplicateSession")) {
                try? env.duplicateSession(session.id)
            }
            Divider()
            Button(L("menu.deleteSession"), role: .destructive) {
                showDeleteConfirmation = true
            }
            .disabled(isActive)
        }
        .confirmationDialog(Text(L("session.deleteConfirm")),
                            isPresented: $showDeleteConfirmation) {
            Button(role: .destructive) {
                try? env.deleteSession(session.id)
            } label: {
                Text(L("deleteSession.permanent"))
            }
            Button(role: .cancel) {
                showDeleteConfirmation = false
            } label: {
                Text(L("deleteSession.cancel"))
            }
        } message: {
            Text(String(format: NSLocalizedString(
                "deleteSession.subtitle", bundle: .module, comment: ""
            ), session.name))
        }
    }

    private var isActive: Bool { env.activeSession?.id == session.id }
    private var isConnecting: Bool { isActive && env.connectionState == .connecting }
    private var indicator: Color {
        guard isActive else { return .gray.opacity(0.4) }
        switch env.connectionState {
        case .connected:  return .green
        case .connecting: return .orange
        case .failed:     return .red
        case .idle:       return .gray
        }
    }
}

private struct DatabaseNode: View {
    @Environment(AppEnvironment.self) private var env
    let name: String

    private var isSelected: Bool {
        if case .database(let n) = env.selectedNode, n == name { return true }
        return false
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { env.expandedDatabases.contains(name) },
                set: { expanded in
                    if expanded { Task { await env.expandDatabase(name) } }
                    else { env.collapseDatabase(name) }
                }
            )
        ) {
            if let tables = env.tablesByDb[name] {
                ForEach(tables) { t in
                    TableNode(database: name, table: t)
                }
            } else {
                Text(L("sidebar.loading"))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } label: {
            Label(name, systemImage: "cylinder")
                .padding(.vertical, 1)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    // 单击 = 选中 + 展开/折叠 + USE 该库
                    env.selectedNode = .database(name)
                    Task { await env.useDatabase(name) }
                    if env.expandedDatabases.contains(name) {
                        env.collapseDatabase(name)
                    } else {
                        Task { await env.expandDatabase(name) }
                    }
                }
        }
    }
}

private struct TableNode: View {
    @Environment(AppEnvironment.self) private var env
    let database: String
    let table: TableMeta
    @State private var showTruncateSheet = false
    @State private var csvImportVM: CSVImportViewModel?

    private var isSelected: Bool {
        switch env.selectedNode {
        case .table(let db, let t):
            return db == database && t == table.name && table.kind == .table
        case .view(let db, let v):
            return db == database && v == table.name && table.kind == .view
        default:
            return false
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: table.kind))
                .foregroundStyle(isSelected ? Color.accentColor : iconColor(for: table.kind))
                .font(.caption)
            Text(table.name)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // 单击：高亮 + 根据类型决定打开方式
            env.selectedNode = (table.kind == .view)
                ? .view(database: database, view: table.name)
                : .table(database: database, table: table.name)
            switch table.kind {
            case .table, .view:
                env.openDataTab(database: database, table: table.name)
            case .procedure, .function, .trigger, .event:
                // 这类对象没数据表 → 打开 Info Tab（展示 CREATE 语句）
                env.openTableInfoTab(database: database, table: table.name)
            }
        }
        .onTapGesture(count: 2) {
            switch table.kind {
            case .table, .view:
                env.openDataTab(database: database, table: table.name)
            default:
                env.openTableInfoTab(database: database, table: table.name)
            }
        }
        .contextMenu {
            Button(L("menu.openData")) {
                env.openDataTab(database: database, table: table.name)
            }
            Button(L("menu.showTableInfo")) {
                env.openTableInfoTab(database: database, table: table.name)
            }
            Divider()
            Button(L("menu.copyTableName")) {
                copyTableName()
            }
            Button(L("menu.copyCreate")) {
                Task { await copyCreateStatement() }
            }
            if table.kind == .table {
                Divider()
                Button(L("menu.importCSV")) {
                    Task { await prepareCSVImport() }
                }
                Button(L("menu.truncateTable"), role: .destructive) {
                    showTruncateSheet = true
                }
            }
        }
        .sheet(isPresented: $showTruncateSheet) {
            TruncateTableSheet(database: database, table: table.name,
                                isPresented: $showTruncateSheet)
                .environment(env)
        }
        // 关键：用 sheet(item:) 等 vm 加载完才弹，否则会闪一个空白小窗
        .sheet(item: $csvImportVM) { vm in
            CSVImportView(vm: vm, env: env, onClose: {
                csvImportVM = nil
            })
        }
    }

    private func prepareCSVImport() async {
        guard let schema = await env.loadTableSchema(database: database, table: table.name)
        else { return }
        // 设置 vm → sheet(item:) 自动弹出
        csvImportVM = CSVImportViewModel(database: database, table: table.name, schema: schema)
    }

    private func iconName(for kind: TableKind) -> String {
        switch kind {
        case .table:     return "tablecells"
        case .view:      return "eye"
        case .procedure: return "function"
        case .function:  return "f.cursive"
        case .trigger:   return "bolt.circle"
        case .event:     return "calendar"
        }
    }
    private func iconColor(for kind: TableKind) -> Color {
        switch kind {
        case .table, .view:    return .secondary
        case .procedure, .function: return .purple
        case .trigger:         return .orange
        case .event:           return .blue
        }
    }

    private func copyTableName() {
        guard let qualified = try? SQLIdentifier.qualified(
            database: database, table: table.name
        ) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(qualified, forType: .string)
    }

    private func copyCreateStatement() async {
        guard let client = env.activeClient,
              let qualified = try? SQLIdentifier.qualified(
                database: database, table: table.name
              ) else { return }
        do {
            let rs = try await client.query("SHOW CREATE TABLE \(qualified)")
            if let row = rs.rows.first, row.count >= 2,
               case .string(let ddl) = row[1] {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(ddl, forType: .string)
            }
        } catch {
            // 静默；future 应有 toast 通道
        }
    }
}

/// PRD §5.2.6 Truncate Table 二次确认。
/// 必须勾选 checkbox 才能确认；失败时 sheet 保留并显示错误。
private struct TruncateTableSheet: View {
    @Environment(AppEnvironment.self) private var env
    let database: String
    let table: String
    @Binding var isPresented: Bool

    @State private var confirmChecked = false
    @State private var running = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(String(format: NSLocalizedString(
                        "truncate.title", bundle: .module, comment: ""
                    ), database, table))
                        .font(.headline)
                    Text(L("truncate.warning"))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $confirmChecked) {
                Text(L("truncate.confirm"))
            }

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button(L("truncate.cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(L("truncate.button")) {
                    Task { await performTruncate() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!confirmChecked || running)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func performTruncate() async {
        guard let client = env.activeClient,
              let qualified = try? SQLIdentifier.qualified(
                database: database, table: table
              ) else { return }
        running = true
        error = nil
        do {
            _ = try await client.exec("TRUNCATE TABLE \(qualified)")
            // 成功 → 关闭弹框
            isPresented = false
            // 刷新打开的对应 Data Tab
            env.notifyTableTruncated(database: database, table: table)
        } catch let e as DBError {
            error = describe(e)
        } catch {
            self.error = String(describing: error)
        }
        running = false
    }

    private func describe(_ e: DBError) -> String {
        switch e {
        case .syntax(let n, _, let m): return "ERROR \(n): \(m)"
        case .auth(let m, _): return "AUTH: \(m)"
        case .network(let m, _): return "NETWORK: \(m)"
        case .server(let n, _, let m): return "SERVER \(n): \(m)"
        case .constraint(let n, _, let m): return "CONSTRAINT \(n): \(m)"
        default: return String(describing: e)
        }
    }
}