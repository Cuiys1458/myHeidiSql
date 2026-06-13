import Foundation
import SwiftUI
import Observation
import MacHeidiCore
import MacHeidiMySQL

/// 进程内单例环境：拥有 Store / Keychain / SessionManager / 活跃连接。
///
/// 用 `@Observable`（Swift 5.9+）暴露给 SwiftUI；所有 mutate 都在 MainActor。
@MainActor
@Observable
public final class AppEnvironment {

    // MARK: 注入

    public let sessionManager: SessionManager

    // MARK: 持久化状态

    public private(set) var sessions: [SessionConfig] = []

    // MARK: 活跃 Session 状态

    public private(set) var activeSession: SessionConfig?
    public private(set) var activeClient: (any DBClient)?
    public private(set) var connectionState: ConnState = .idle

    public enum ConnState: Equatable {
        case idle
        case connecting
        case connected
        case failed(message: String)
    }

    /// 非用户主动断开时为 true → 显示主窗顶部 banner（PRD R10）
    public private(set) var connectionLost: Bool = false

    /// 服务器信息，连接成功后填充（PRD §6.4 状态栏）。
    public private(set) var serverInfo: ServerInfo?

    public struct ServerInfo: Equatable, Sendable {
        public let version: String
        public let sqlMode: String
        public let timeZone: String
    }

    /// 当前活跃连接的心跳调度器；disconnect 时停掉。
    private var heartbeat: HeartbeatScheduler?

    // MARK: 主区 Tab

    public private(set) var openTabs: [WorkspaceTab] = []
    public var selectedTabId: WorkspaceTab.ID?

    // MARK: 对象树缓存

    public private(set) var databases: [String] = []
    public private(set) var tablesByDb: [String: [TableMeta]] = [:]
    public var expandedDatabases: Set<String> = []

    /// 当前选中的对象树节点（用于左栏高亮 / 右栏 Table Info Tab）。
    public var selectedNode: TreeSelection?

    public enum TreeSelection: Hashable, Sendable {
        case session(UUID)
        case database(String)
        case table(database: String, table: String)
        case view(database: String, view: String)
    }

    // MARK: 构造

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        reloadSessions()
    }

    public static func make() -> AppEnvironment {
        let dir = appSupportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = JSONSessionStore(directory: dir)
        let keychain = MacOSKeychainStore()
        let mgr = SessionManager(store: store, keychain: keychain)
        return AppEnvironment(sessionManager: mgr)
    }

    private static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("MacHeidi", isDirectory: true)
    }

    // MARK: Session CRUD

    public func reloadSessions() {
        sessions = (try? sessionManager.loadAll()) ?? []
    }

    public func addSession(_ s: SessionConfig) throws {
        try sessionManager.add(s)
        reloadSessions()
    }

    public func updateSession(_ s: SessionConfig) throws {
        try sessionManager.update(s)
        reloadSessions()
    }

    public func deleteSession(_ id: UUID) throws {
        if activeSession?.id == id {
            disconnectActive()
        }
        try sessionManager.delete(id)
        reloadSessions()
    }

    public func duplicateSession(_ id: UUID) throws {
        _ = try sessionManager.duplicate(id)
        reloadSessions()
    }

    // MARK: Connect

    public func openSession(_ session: SessionConfig) async {
        disconnectActive()
        // 从 Keychain 单独读密码 —— 避免列表里给每个 session 都读触发多次弹窗
        var withPassword = session
        if withPassword.password.isEmpty {
            if let loaded = try? sessionManager.loadOneWithPassword(id: session.id) {
                withPassword = loaded
            }
        }
        activeSession = withPassword
        connectionState = .connecting

        // 如果配了 SSH 隧道，先起本地转发
        var effectiveHost = withPassword.hostname
        var effectivePort = withPassword.port
        if let ssh = withPassword.sshConfig, ssh.isEnabled {
            do {
                let local = try SSHTunnel.shared.start(
                    forDB: withPassword.hostname, port: withPassword.port, ssh: ssh
                )
                effectiveHost = "127.0.0.1"
                effectivePort = local
            } catch {
                connectionState = .failed(message: "SSH tunnel failed: \(error.localizedDescription)")
                activeClient = nil
                return
            }
        }

        let client = MySQLClient()
        let cfg = ConnectionConfig(
            hostname: effectiveHost,
            port: effectivePort,
            user: withPassword.user,
            password: withPassword.password,
            // defaultDatabases 是"白名单"（逗号分隔），可能多个；只取第一个传给 USE。
            // 这样 Query Tab 里裸跑 SELECT 不会撞 "No database selected"。
            defaultDatabase: firstDefaultDatabase(withPassword.defaultDatabases),
            useSSL: withPassword.useSSL,
            connectTimeout: .seconds(10),
            queryTimeout: nil
        )
        do {
            try await client.connect(cfg)
            activeClient = client
            connectionState = .connected
            connectionLost = false
            currentDatabase = firstDefaultDatabase(withPassword.defaultDatabases)
            await loadServerInfo(client: client)
            await refreshDatabases()
            // 自动开第一个 Query Tab
            if !openTabs.contains(where: { if case .query = $0.kind { return true } else { return false } }) {
                openNewQueryTab()
            }
            // 启动心跳（PRD R10）
            startHeartbeat(for: client)
        } catch let err as DBError {
            connectionState = .failed(message: describe(err))
            activeClient = nil
        } catch {
            connectionState = .failed(message: String(describing: error))
            activeClient = nil
        }
    }

    /// 用户主动断开 —— 不显示"Connection lost" banner。
    public func disconnectActive() {
        stopHeartbeat()
        if let c = activeClient { Task { await c.disconnect() } }
        SSHTunnel.shared.stop()
        activeClient = nil
        activeSession = nil
        connectionState = .idle
        connectionLost = false
        serverInfo = nil
        currentDatabase = nil
        databases = []
        tablesByDb = [:]
        expandedDatabases = []
        selectedNode = nil
        openTabs = []
        selectedTabId = nil
    }

    /// 拉取 server 元信息：version + sql_mode + @@time_zone（PRD §6.4）。
    private func loadServerInfo(client: any DBClient) async {
        do {
            let rs = try await client.query("SELECT VERSION(), @@sql_mode, @@time_zone")
            guard let row = rs.rows.first, row.count >= 3 else { return }
            let version = stringValueAny(row[0]) ?? "?"
            let sqlMode = stringValueAny(row[1]) ?? ""
            let tz = stringValueAny(row[2]) ?? "?"
            serverInfo = ServerInfo(version: version, sqlMode: sqlMode, timeZone: tz)
        } catch {
            // 不致命；状态栏只是补充
        }
    }

    /// 拉取表结构（列 + PK）—— 编辑模式的前置（PRD §5.3.6, §5.3.7）。
    public func loadTableSchema(database: String, table: String) async -> TableSchema? {
        guard let c = activeClient else { return nil }
        let qualified: String
        do { qualified = try SQLIdentifier.qualified(database: database, table: table) }
        catch { return nil }
        do {
            let rs = try await c.query("SHOW FULL COLUMNS FROM \(qualified)")
            var cols: [ColumnMeta] = []
            var pk: [String] = []
            for row in rs.rows {
                guard row.count >= 9 else { continue }
                guard let name = stringFromAny(row[0]),
                      let mysqlType = stringFromAny(row[1]) else { continue }
                let nullStr   = stringFromAny(row[3]) ?? "YES"
                let keyStr    = stringFromAny(row[4]) ?? ""
                let extraStr  = stringFromAny(row[6]) ?? ""
                let commentStr = stringFromAny(row[8]) ?? ""

                let nullable = nullStr.uppercased() == "YES"
                let isAutoInc = extraStr.lowercased().contains("auto_increment")
                let isUnsigned = mysqlType.lowercased().contains("unsigned")
                let normalized = inferNormalizedType(from: mysqlType)

                cols.append(ColumnMeta(
                    name: name, mysqlType: mysqlType, normalizedType: normalized,
                    nullable: nullable, defaultValue: nil, isAutoIncrement: isAutoInc,
                    isUnsigned: isUnsigned, maxLength: nil, precision: nil, scale: nil,
                    comment: commentStr
                ))
                if keyStr == "PRI" { pk.append(name) }
            }
            // 索引
            let indices = await loadIndices(database: database, table: table)
            return TableSchema(columns: cols, primaryKey: pk, indices: indices)
        } catch {
            return nil
        }
    }

    /// 拉 SHOW INDEX，按 Key_name 聚合多列。
    private func loadIndices(database: String, table: String) async -> [IndexMeta] {
        guard let c = activeClient else { return [] }
        let qualified: String
        do { qualified = try SQLIdentifier.qualified(database: database, table: table) }
        catch { return [] }
        guard let rs = try? await c.query("SHOW INDEX FROM \(qualified)") else {
            return []
        }
        // SHOW INDEX 列：Table, Non_unique, Key_name, Seq_in_index, Column_name, ...
        var byName: [String: (cols: [(seq: Int, name: String)], unique: Bool)] = [:]
        for row in rs.rows {
            guard row.count >= 5 else { continue }
            let nonUniqueStr = stringFromAny(row[1]) ?? "1"
            let keyName = stringFromAny(row[2]) ?? ""
            let seqStr = stringFromAny(row[3]) ?? "0"
            let colName = stringFromAny(row[4]) ?? ""
            guard !keyName.isEmpty, !colName.isEmpty else { continue }
            let unique = (nonUniqueStr == "0")
            let seq = Int(seqStr) ?? 0
            var entry = byName[keyName] ?? (cols: [], unique: unique)
            entry.cols.append((seq, colName))
            byName[keyName] = entry
        }
        return byName.map { (name, entry) in
            let sorted = entry.cols.sorted { $0.seq < $1.seq }.map(\.name)
            return IndexMeta(name: name, columns: sorted, unique: entry.unique)
        }.sorted { $0.name < $1.name }
    }

    /// 当前对话已 USE 的数据库（HeidiSQL 行为）。
    /// 侧栏单击库 / 双击表时自动切到对应库；状态栏显示。
    public private(set) var currentDatabase: String?

    /// 切换到指定数据库。在主连接上发 `USE \`db\``。
    public func useDatabase(_ name: String) async {
        guard let client = activeClient else { return }
        do {
            let q = try SQLIdentifier.quote(name)
            _ = try await client.exec("USE \(q)")
            currentDatabase = name
        } catch {
            // 静默：库可能没权限；不致命
        }
    }

    /// "app_prod, app_test" → "app_prod"。空 → nil。
    private func firstDefaultDatabase(_ raw: String) -> String? {
        let names = raw.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return names.first
    }

    /// 给 SQL 编辑器自动补全用：聚合当前 session 的 db / 表名 / 已加载列。
    ///
    /// **不主动**展开任何库 —— 只读已经在 `tablesByDb` 里的缓存。
    /// 用户展开过的库 / 当前默认库会自然补充进来；没展开过就没数据，符合用户预期。
    public func completionSchemaSnapshot() async -> CompletionEngine.SchemaSnapshot {
        var columnsByTable: [String: [String]] = [:]
        var allTables: [String] = []

        let activeDb = currentDatabase

        // 已经在缓存里的库才参与（不主动展开 → 不会强制 SidebarView 全部 expand）
        for (db, tables) in tablesByDb {
            for t in tables where t.kind == .table || t.kind == .view {
                allTables.append(t.name)
                let alreadyOpen = openTabs.contains {
                    if case .data(let d, let n) = $0.kind { return d == db && n == t.name }
                    if case .tableInfo(let d, let n) = $0.kind { return d == db && n == t.name }
                    return false
                }
                let isInActiveDb = (db == activeDb)
                if (alreadyOpen || isInActiveDb) && columnsByTable[t.name] == nil {
                    if let schema = await loadTableSchema(database: db, table: t.name) {
                        columnsByTable[t.name] = schema.columns.map(\.name)
                    }
                }
            }
        }
        return CompletionEngine.SchemaSnapshot(
            databases: databases,
            tables: Array(Set(allTables)).sorted(),
            columnsByTable: columnsByTable
        )
    }

    /// 返回简化结构：[(constraint, column, refDb, refTable, refCol)]
    public func loadForeignKeys(database: String, table: String)
        async -> [ForeignKeyEntry] {
        guard let c = activeClient else { return [] }
        let safeDb = database.replacingOccurrences(of: "'", with: "''")
        let safeTb = table.replacingOccurrences(of: "'", with: "''")
        let sql = """
        SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_SCHEMA,
               REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = '\(safeDb)' AND TABLE_NAME = '\(safeTb)'
              AND REFERENCED_TABLE_NAME IS NOT NULL
        ORDER BY CONSTRAINT_NAME, ORDINAL_POSITION
        """
        guard let rs = try? await c.query(sql) else { return [] }
        return rs.rows.compactMap { row in
            guard row.count >= 5,
                  let cn = stringFromAny(row[0]),
                  let col = stringFromAny(row[1]),
                  let refTb = stringFromAny(row[3]),
                  let refCol = stringFromAny(row[4]) else { return nil }
            let refDb = stringFromAny(row[2]) ?? ""
            return ForeignKeyEntry(constraint: cn, column: col,
                                    refDatabase: refDb, refTable: refTb, refColumn: refCol)
        }
    }

    public struct ForeignKeyEntry: Sendable, Hashable {
        public let constraint: String
        public let column: String
        public let refDatabase: String
        public let refTable: String
        public let refColumn: String
    }

    /// 比 stringValueAny 更宽松：`.blob` 也按 UTF-8 文本解析。
    /// MySQL 8 的 INFORMATION_SCHEMA 类查询中字符串列会用 VARBINARY，
    /// 驱动归类为 .blob，这里恢复成 string。
    private func stringFromAny(_ c: CellValue) -> String? {
        switch c {
        case .string(let s): return s
        case .int(let v): return String(v)
        case .uint(let v): return String(v)
        case .blob(let d): return String(data: d, encoding: .utf8)
        case .json(let s): return s
        case .unknown(let s): return s
        case .null: return nil
        default: return nil
        }
    }

    private func stringValueAny(_ c: CellValue) -> String? {
        switch c {
        case .string(let s): return s
        case .int(let v): return String(v)
        case .uint(let v): return String(v)
        case .null: return nil
        default: return nil
        }
    }

    private func inferNormalizedType(from mysqlType: String) -> NormalizedType {
        let t = mysqlType.lowercased()
        if t.hasPrefix("tinyint(1)") { return .bool }
        if t.contains("decimal") || t.contains("numeric") { return .decimal }
        if t.contains("int")    { return .int }
        if t.contains("float") || t.contains("double") || t.contains("real") { return .double }
        if t.contains("datetime") || t.contains("timestamp") { return .datetime }
        if t == "date" || t.hasPrefix("date(") { return .date }
        if t.contains("time") { return .time }
        if t.contains("json") { return .json }
        if t.contains("blob") || t.contains("binary") { return .blob }
        return .string
    }

    /// 心跳失败导致的"非主动断开" —— 显示 banner，保留 activeSession 让用户能 Reconnect。
    func handleConnectionLost() {
        stopHeartbeat()
        if let c = activeClient { Task { await c.disconnect() } }
        activeClient = nil
        connectionState = .failed(message: "Connection lost")
        connectionLost = true
    }

    /// 点击 banner 的 Reconnect 按钮触发的重连。
    public func reconnectActive() async {
        guard let s = activeSession else { return }
        connectionLost = false
        await openSession(s)
    }

    // MARK: 心跳（PRD R10）

    private func startHeartbeat(for client: any DBClient) {
        let hb = HeartbeatScheduler(
            interval: .seconds(30),
            probe: { [weak client] in
                guard let client else { return false }
                do {
                    _ = try await client.query("SELECT 1")
                    return true
                } catch {
                    return false
                }
            },
            onDisconnect: { @MainActor [weak self] in
                self?.handleConnectionLost()
            }
        )
        heartbeat = hb
        Task { await hb.start() }
    }

    private func stopHeartbeat() {
        if let hb = heartbeat {
            Task { await hb.stop() }
        }
        heartbeat = nil
    }

    private func describe(_ e: DBError) -> String {
        switch e {
        case .network(let m, _): return "Network: \(m)"
        case .auth(let m, let n): return "Auth (\(n.map { "\($0)" } ?? "?")): \(m)"
        case .syntax(let n, _, let m): return "Syntax \(n): \(m)"
        case .constraint(let n, _, let m): return "Constraint \(n): \(m)"
        case .timeout(let m): return "Timeout: \(m)"
        case .cancelled: return "Cancelled"
        case .server(let n, _, let m): return "Server \(n): \(m)"
        case .unknown(let m, _): return m
        }
    }

    // MARK: 对象树

    public func refreshDatabases() async {
        guard let c = activeClient else { return }
        do {
            let all = try await c.listDatabases(includeSystem: true)
            databases = DatabaseFilter.apply(
                all,
                defaultDatabases: activeSession?.defaultDatabases ?? ""
            )
        } catch {
            databases = []
        }
    }

    public func expandDatabase(_ db: String) async {
        expandedDatabases.insert(db)
        guard let c = activeClient, tablesByDb[db] == nil else { return }
        do {
            // SHOW FULL TABLES FROM `<db>` → 列为 [Name, Table_type]
            let rs = try await c.query("SHOW FULL TABLES FROM `\(db)`")
            var combined: [TableMeta] = rs.rows.compactMap { row in
                guard let name = stringFromAny(row.first ?? .null) else { return nil }
                let kind: TableKind = {
                    if row.count > 1, let t = stringFromAny(row[1]) {
                        return t.uppercased().contains("VIEW") ? .view : .table
                    }
                    return .table
                }()
                return TableMeta(name: name, kind: kind, engine: nil,
                                 rowCountEstimate: nil, comment: "")
            }
            // 存储过程
            if let rs2 = try? await c.query(
                "SELECT ROUTINE_NAME, ROUTINE_TYPE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '\(escapeIdent(db))'"
            ) {
                for row in rs2.rows {
                    guard row.count >= 2,
                          let name = stringFromAny(row[0]),
                          let typ = stringFromAny(row[1]) else { continue }
                    let kind: TableKind = (typ.uppercased() == "FUNCTION") ? .function : .procedure
                    combined.append(TableMeta(name: name, kind: kind, engine: nil,
                                              rowCountEstimate: nil, comment: ""))
                }
            }
            // 触发器
            if let rs3 = try? await c.query(
                "SELECT TRIGGER_NAME FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = '\(escapeIdent(db))'"
            ) {
                for row in rs3.rows {
                    guard let name = stringFromAny(row.first ?? .null) else { continue }
                    combined.append(TableMeta(name: name, kind: .trigger, engine: nil,
                                              rowCountEstimate: nil, comment: ""))
                }
            }
            tablesByDb[db] = combined
        } catch {
            tablesByDb[db] = []
        }
    }

    private func escapeIdent(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }

    public func collapseDatabase(_ db: String) {
        expandedDatabases.remove(db)
    }

    // MARK: Tab

    public func openNewQueryTab() {
        let n = (openTabs.compactMap {
            if case .query(let title) = $0.kind, let num = Int(title.replacingOccurrences(of: "Query #", with: "")) { return num }
            return nil
        }.max() ?? 0) + 1
        let tab = WorkspaceTab(kind: .query(title: "Query #\(n)"))
        openTabs.append(tab)
        selectedTabId = tab.id
    }

    public func openDataTab(database: String, table: String) {
        // 自动切到该库 —— Query Tab 后续裸表名也能跑
        if currentDatabase != database {
            Task { await useDatabase(database) }
        }
        if let existing = openTabs.first(where: {
            if case .data(let db, let t) = $0.kind { return db == database && t == table } else { return false }
        }) {
            selectedTabId = existing.id
            return
        }
        let tab = WorkspaceTab(kind: .data(database: database, table: table))
        openTabs.append(tab)
        selectedTabId = tab.id
    }

    /// 单击表打开 Table Info Tab（PRD §5.2.3）。同表只一个 tab。
    public func openTableInfoTab(database: String, table: String) {
        if let existing = openTabs.first(where: {
            if case .tableInfo(let db, let t) = $0.kind { return db == database && t == table } else { return false }
        }) {
            selectedTabId = existing.id
            return
        }
        let tab = WorkspaceTab(kind: .tableInfo(database: database, table: table))
        openTabs.append(tab)
        selectedTabId = tab.id
    }

    /// F5 刷新当前选中节点（PRD §5.2.5）。
    public func refreshSelected() async {
        let sel = mapSelection()
        let target = RefreshPolicy.target(for: sel)
        switch target {
        case .sessionDatabases:
            await refreshDatabases()
        case .databaseTables(let db):
            tablesByDb[db] = nil
            // 重新拉
            if expandedDatabases.contains(db) {
                await expandDatabase(db)
            }
        }
    }

    private func mapSelection() -> RefreshSelection {
        switch selectedNode {
        case .none: return .none
        case .session: return .session
        case .database(let n): return .database(n)
        case .table(let d, let t): return .table(database: d, table: t)
        case .view(let d, let v): return .view(database: d, view: v)
        }
    }

    /// Truncate 成功后通知打开的 Data Tab 刷新（PRD §5.2.6 第 5 步）。
    /// 通过递增 `tableRefreshTicker` 触发 SwiftUI 重渲染对应 Tab。
    public func notifyTableTruncated(database: String, table: String) {
        tableRefreshTicker[TableKey(database: database, table: table), default: 0] += 1
    }

    public struct TableKey: Hashable, Sendable {
        public let database: String
        public let table: String
        public init(database: String, table: String) {
            self.database = database
            self.table = table
        }
    }

    public private(set) var tableRefreshTicker: [TableKey: Int] = [:]

    /// 从 History 选了一条 SQL → 灌给下一个新建的 Query Tab。
    /// QueryTabView .task 中读取并清空。
    public var pendingHistorySQL: String?

    /// 每个 Query Tab 的 SQL 文本 + 光标偏移。
    /// 由 AppEnvironment 持有 → 切换 Tab 不丢、关闭 Tab 时清。
    public var queryTabSQL: [UUID: String] = [:]
    public var queryTabCursor: [UUID: Int] = [:]

    public func closeTab(_ id: WorkspaceTab.ID) {
        openTabs.removeAll { $0.id == id }
        queryTabSQL.removeValue(forKey: id)
        queryTabCursor.removeValue(forKey: id)
        if selectedTabId == id { selectedTabId = openTabs.last?.id }
    }
}

// MARK: - TableKind / TableMeta（补 MacHeidiCore 缺的轻量类型）

public enum TableKind: String, Sendable, Equatable {
    case table, view, procedure, function, trigger, event
}

public struct TableMeta: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let kind: TableKind
    public let engine: String?
    public let rowCountEstimate: UInt64?
    public let comment: String

    public init(name: String, kind: TableKind, engine: String?,
                rowCountEstimate: UInt64?, comment: String) {
        self.name = name; self.kind = kind; self.engine = engine
        self.rowCountEstimate = rowCountEstimate; self.comment = comment
    }
}

// MARK: - Workspace Tab

public struct WorkspaceTab: Identifiable, Equatable {
    public let id: UUID
    public let kind: Kind

    public enum Kind: Equatable {
        case query(title: String)
        case data(database: String, table: String)
        case tableInfo(database: String, table: String)
    }

    public init(id: UUID = UUID(), kind: Kind) {
        self.id = id; self.kind = kind
    }

    public var title: String {
        switch kind {
        case .query(let t): return t
        case .data(_, let t): return t
        case .tableInfo(_, let t): return "ⓘ \(t)"
        }
    }
}
