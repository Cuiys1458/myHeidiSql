import Foundation
import Observation
import MacHeidiCore

/// Data Tab 的 ViewModel：持有结果集 + Pending Edits + 提交流程。
///
/// 所有 SQL 生成委托给 `SQLGenerator`（已被 31 个单测锁住）。
/// VM 只负责：编排 schema 加载、commit 单事务、错误回报。
@MainActor
@Observable
final class DataTabViewModel {

    // MARK: 入参

    let database: String
    let table: String

    // MARK: 显式状态

    private(set) var resultSet: ResultSet?
    private(set) var schema: TableSchema?
    private(set) var totalRows: UInt64?
    private(set) var loading: Bool = false
    private(set) var error: String?
    private(set) var commitError: String?

    /// MySQL `SHOW WARNINGS` 返回的告警，显示在 UI 顶部黄条。
    /// 关键场景：WHERE `int_col = '某中文'` 时 MySQL 静默把字符串当 0，
    /// 没有 warning 用户根本不知道结果为啥不对。
    private(set) var warnings: [String] = []

    /// 当前编辑状态
    private(set) var pending = PendingEdits()

    /// 分页状态（PRD §5.3.5）
    private(set) var pagination: Pagination

    /// commit 成功的 ticker —— View 监听此值变化触发 reload。
    private(set) var commitSuccessFlag: Bool = false

    /// 客户端列头排序状态。`nil` = 不排序，按 SQL 原顺序。
    var sortColumn: String?
    var sortAscending: Bool = true

    /// 应用客户端排序后的行（保留与原始 rowIdx 的映射，用于编辑回写）。
    func sortedRowsWithOrigIdx() -> [(row: [CellValue], origIdx: Int)] {
        guard let rs = resultSet else { return [] }
        let pairs = Array(rs.rows.enumerated()).map { (row: $0.element, origIdx: $0.offset) }
        guard let key = sortColumn,
              let colIdx = rs.columns.firstIndex(where: { $0.name == key }) else {
            return pairs
        }
        let asc = sortAscending
        return pairs.sorted { a, b in
            let av = a.row[colIdx]
            let bv = b.row[colIdx]
            if let an = numeric(av), let bn = numeric(bv) {
                return asc ? an < bn : an > bn
            }
            let s1 = stringForSort(av)
            let s2 = stringForSort(bv)
            return asc ? s1 < s2 : s1 > s2
        }
    }

    private func numeric(_ v: CellValue) -> Double? {
        switch v {
        case .int(let n):  return Double(n)
        case .uint(let n): return Double(n)
        case .double(let d): return d
        case .decimal(let s): return Double(s)
        default: return nil
        }
    }
    private func stringForSort(_ v: CellValue) -> String {
        switch v {
        case .null: return ""
        case .string(let s), .json(let s), .time(let s),
             .decimal(let s), .unknown(let s): return s
        case .int(let n): return String(n)
        case .uint(let n): return String(n)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "1" : "0"
        case .date(let d), .datetime(let d):
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = .current
            return f.string(from: d)
        case .blob: return ""
        }
    }

    func toggleSort(column: String) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    /// PRD §5.3.7.2：无 PK 表 commit 前需要二次确认
    var pendingCommitConfirmation: NoPKConfirmation?

    /// 是否有未提交修改
    var hasPending: Bool { !pending.isEmpty }
    var pendingSummary: String {
        let updates = pending.dirtyRowIds.count
        let inserts = pending.pendingInserts.filter(\.hasUserSetValues).count
        let deletes = pending.deletedRowIds.count
        var parts: [String] = []
        if updates > 0 { parts.append("\(updates) update\(updates == 1 ? "" : "s")") }
        if inserts > 0 { parts.append("\(inserts) insert\(inserts == 1 ? "" : "s")") }
        if deletes > 0 { parts.append("\(deletes) delete\(deletes == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    init(database: String, table: String) {
        self.database = database
        self.table = table
        // 启动时用持久化的 page size
        let saved = UserPreferences.shared.pageSize
        self.pagination = Pagination(total: nil, pageSize: saved, currentPage: 1)
    }

    // MARK: load

    func load(env: AppEnvironment, whereClause: String, limit: Int) async {
        // limit 参数现在仅用于初次进入；之后由 pagination 控制
        // 保留参数兼容旧调用站点
        _ = limit
        await loadCurrentPage(env: env, whereClause: whereClause)
    }

    /// 用当前 `pagination` 状态拉数据。
    func loadCurrentPage(env: AppEnvironment, whereClause: String) async {
        guard let client = env.activeClient else { return }
        loading = true
        error = nil
        commitError = nil
        defer { loading = false }

        // 1. schema（编辑必需）
        if schema == nil {
            schema = await env.loadTableSchema(database: database, table: table)
        }

        let qualified: String
        do { qualified = try SQLIdentifier.qualified(database: database, table: table) }
        catch {
            self.error = "Invalid table name"
            return
        }

        let whereSQL = whereClause.isEmpty ? "" : "WHERE \(whereClause)"
        let dataSQL  = "SELECT * FROM \(qualified) \(whereSQL) " +
                       "LIMIT \(pagination.limit) OFFSET \(pagination.offset)"
        let countSQL = "SELECT COUNT(*) FROM \(qualified) \(whereSQL)"

        do {
            // 串行：先拉数据，再立刻拉 warnings（warnings 是 session-level，
            // 任何后续语句都会清空它），最后才并行 COUNT(*)
            let data = try await client.query(dataSQL)
            self.resultSet = data
            // 加载新数据 → 清掉旧 pending（数据可能已变）
            self.pending = PendingEdits()
            await loadWarnings(client: client)

            if let countRs = try? await client.query(countSQL),
               let cell = countRs.rows.first?.first {
                let newTotal = extractCount(cell)
                totalRows = newTotal
                pagination = pagination.withTotal(newTotal)
            } else {
                pagination = pagination.withTotal(nil)
            }
        } catch let e as DBError {
            self.error = describe(e)
        } catch {
            self.error = String(describing: error)
        }
    }

    /// SHOW WARNINGS 抓最近的告警（隐式类型转换、截断、超范围等）。
    private func loadWarnings(client: any DBClient) async {
        warnings = []
        do {
            let rs = try await client.query("SHOW WARNINGS")
            for row in rs.rows {
                guard row.count >= 3 else { continue }
                let level: String = {
                    if case .string(let s) = row[0] { return s }
                    return ""
                }()
                let code: String = {
                    if case .int(let v) = row[1]  { return String(v) }
                    if case .uint(let v) = row[1] { return String(v) }
                    return ""
                }()
                let message: String = {
                    if case .string(let s) = row[2] { return s }
                    return ""
                }()
                warnings.append("\(level) \(code): \(message)")
            }
        } catch {
            // SHOW WARNINGS 失败不致命，继续
        }
    }

    // MARK: pagination transitions

    func goToPage(_ page: Int, env: AppEnvironment, whereClause: String) async {
        pagination = pagination.withPage(page)
        await loadCurrentPage(env: env, whereClause: whereClause)
    }
    func goFirst(env: AppEnvironment, whereClause: String) async {
        await goToPage(1, env: env, whereClause: whereClause)
    }
    func goPrev(env: AppEnvironment, whereClause: String) async {
        await goToPage(pagination.currentPage - 1, env: env, whereClause: whereClause)
    }
    func goNext(env: AppEnvironment, whereClause: String) async {
        await goToPage(pagination.currentPage + 1, env: env, whereClause: whereClause)
    }
    func goLast(env: AppEnvironment, whereClause: String) async {
        guard let pages = pagination.totalPages else { return }
        await goToPage(pages, env: env, whereClause: whereClause)
    }
    func setPageSize(_ size: Int, env: AppEnvironment, whereClause: String) async {
        UserPreferences.shared.pageSize = size
        pagination = pagination.withPageSize(size)
        await loadCurrentPage(env: env, whereClause: whereClause)
    }

    /// WHERE 改变 / Refresh → 重置到第 1 页
    func resetToFirstPage(env: AppEnvironment, whereClause: String) async {
        pagination = pagination.withPage(1)
        await loadCurrentPage(env: env, whereClause: whereClause)
    }

    // MARK: edit operations

    /// 用户编辑了一个单元格（已经过 CellValueParser 校验）。
    func editCell(rowIdx: Int, columnIndex: Int, newValue: CellValue) {
        guard let rs = resultSet, let schema = schema,
              rowIdx < rs.rows.count else { return }
        let rowId = self.rowId(for: rowIdx)
        pending.editCell(
            rowId: rowId,
            originalValues: rs.rows[rowIdx],
            columnIndex: columnIndex,
            newValue: newValue,
            columns: schema.columns
        )
    }

    func newValue(rowIdx: Int, column: String) -> CellValue? {
        guard rowIdx < (resultSet?.rows.count ?? 0) else { return nil }
        let rowId = self.rowId(for: rowIdx)
        return pending.dirtyCells(rowId: rowId)[column]
    }

    func isCellDirty(rowIdx: Int, column: String) -> Bool {
        newValue(rowIdx: rowIdx, column: column) != nil
    }

    func isRowDirty(rowIdx: Int) -> Bool {
        let rowId = self.rowId(for: rowIdx)
        return pending.isDirty(rowId: rowId)
    }

    func isRowMarkedForDeletion(rowIdx: Int) -> Bool {
        let rowId = self.rowId(for: rowIdx)
        return pending.isMarkedForDeletion(rowId: rowId)
    }

    func toggleRowDeletion(rowIdx: Int) {
        let rowId = self.rowId(for: rowIdx)
        if pending.isMarkedForDeletion(rowId: rowId) {
            pending.unmarkRowDelete(rowId: rowId)
        } else {
            pending.markRowDelete(rowId: rowId)
        }
    }

    func discardAll() {
        pending.discard()
        commitError = nil
    }

    // MARK: insert

    @discardableResult
    func addInsertRow() -> UUID {
        return pending.addNewRow(initialValues: [:])
    }

    func setInsertCell(localId: UUID, column: String, value: CellValue) {
        pending.setInsertCell(localId: localId, column: column, value: value)
    }

    func removeInsertRow(localId: UUID) {
        pending.removeInsertRow(localId: localId)
    }

    // MARK: commit (PRD §5.3.7.1 单事务)

    /// 准备提交。无 PK 表先弹二次确认；用户确认后再调 ``performCommit``。
    /// 有 PK 表直接执行。
    func attemptCommit(env: AppEnvironment) async {
        guard let schema = schema, hasPending else { return }
        if !schema.hasPrimaryKey {
            // 收集影响计数 + 排除列警告，让 UI 展示给用户
            let updates = pending.dirtyRowIds.count
            let inserts = pending.pendingInserts.filter(\.hasUserSetValues).count
            let deletes = pending.deletedRowIds.count
            pendingCommitConfirmation = NoPKConfirmation(
                updates: updates, inserts: inserts, deletes: deletes
            )
            return
        }
        await performCommit(env: env)
    }

    /// commit 成功 / 失败后由 view 调用，传入当前 where；这样不需要 VM 缓存 where。
    func reloadAfterCommit(env: AppEnvironment, whereClause: String) async {
        await loadCurrentPage(env: env, whereClause: whereClause)
    }

    func performCommit(env: AppEnvironment) async {
        pendingCommitConfirmation = nil
        guard let client = env.activeClient,
              let schema = schema,
              let rs = resultSet else { return }

        commitError = nil

        // 收集所有要执行的 SQL
        var statements: [String] = []
        do {
            // UPDATEs
            for rowId in pending.dirtyRowIds {
                guard let rowIdx = rowIndex(forRowId: rowId, in: rs) else { continue }
                let changed = pending.dirtyCells(rowId: rowId)
                guard !changed.isEmpty else { continue }
                let sql = try SQLGenerator.update(
                    database: database, table: table, schema: schema,
                    originalRow: rs.rows[rowIdx],
                    changedColumns: changed
                )
                statements.append(sql)
            }
            // INSERTs（仅 hasUserSetValues 的）
            for row in pending.pendingInserts where row.hasUserSetValues {
                let sql = try SQLGenerator.insert(
                    database: database, table: table, schema: schema,
                    values: row.values
                )
                statements.append(sql)
            }
            // DELETEs
            for rowId in pending.deletedRowIds {
                guard let rowIdx = rowIndex(forRowId: rowId, in: rs) else { continue }
                let sql = try SQLGenerator.delete(
                    database: database, table: table, schema: schema,
                    originalRow: rs.rows[rowIdx]
                )
                statements.append(sql)
            }
        } catch {
            commitError = "Failed to generate SQL: \(error)"
            return
        }

        guard !statements.isEmpty else { return }

        // 执行单事务
        do {
            _ = try await client.exec("START TRANSACTION")
            for sql in statements {
                _ = try await client.exec(sql)
            }
            _ = try await client.exec("COMMIT")
            // 成功 → 清 pending；调用方负责 reload (它知道 whereClause)
            pending = PendingEdits()
            commitSuccessFlag.toggle()
        } catch let e as DBError {
            // ROLLBACK 不抛
            _ = try? await client.exec("ROLLBACK")
            commitError = describe(e)
        } catch {
            _ = try? await client.exec("ROLLBACK")
            commitError = String(describing: error)
        }
    }

    // MARK: row id 策略

    /// 用 (PK) 拼字符串作为稳定 rowId；没有 PK 时退化为行索引（仅本次加载有效）。
    private func rowId(for rowIdx: Int) -> String {
        guard let rs = resultSet, let schema = schema,
              rowIdx < rs.rows.count else { return "row_\(rowIdx)" }
        guard !schema.primaryKey.isEmpty else { return "row_\(rowIdx)" }
        let parts = schema.primaryKey.compactMap { name -> String? in
            guard let idx = schema.columns.firstIndex(where: { $0.name == name }),
                  idx < rs.rows[rowIdx].count else { return nil }
            return SQLGenerator.literal(rs.rows[rowIdx][idx])
        }
        return parts.joined(separator: "::")
    }

    private func rowIndex(forRowId targetId: String, in rs: ResultSet) -> Int? {
        for i in 0..<rs.rows.count {
            if rowId(for: i) == targetId { return i }
        }
        return nil
    }

    /// 流式导出整张表。按 chunkSize 分批 SELECT，逐块写文件。
    /// - Parameters:
    ///   - to: 目标文件 URL
    ///   - format: csv/tsv/sql
    ///   - whereClause: 当前 WHERE 过滤（不含 "WHERE"）
    ///   - chunkSize: 每批拉多少行
    ///   - progress: 已写入行数回调（主线程）
    /// - Returns: 已写入总行数
    @discardableResult
    func exportAll(
        to url: URL,
        format: ResultExporter.Format,
        whereClause: String,
        env: AppEnvironment,
        chunkSize: Int = 1000,
        progress: @escaping (UInt64) -> Void
    ) async throws -> UInt64 {
        guard let client = env.activeClient else {
            throw NSError(domain: "Export", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        let qualified = try SQLIdentifier.qualified(database: database, table: table)
        let whereSQL = whereClause.isEmpty ? "" : "WHERE \(whereClause)"

        // 创建 / 清空文件
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        var offset: UInt64 = 0
        var firstChunk = true
        while !Task.isCancelled {
            let sql = "SELECT * FROM \(qualified) \(whereSQL) LIMIT \(chunkSize) OFFSET \(offset)"
            let rs = try await client.query(sql)
            if rs.rows.isEmpty { break }
            try ResultExporter.appendChunk(
                to: handle, chunk: rs, format: format,
                isFirstChunk: firstChunk,
                database: database, table: table
            )
            firstChunk = false
            offset += UInt64(rs.rows.count)
            progress(offset)
            if rs.rows.count < chunkSize { break }
        }
        return offset
    }

    private func extractCount(_ c: CellValue) -> UInt64? {
        switch c {
        case .int(let v):  return v < 0 ? nil : UInt64(v)
        case .uint(let v): return v
        case .string(let s): return UInt64(s)
        case .decimal(let s): return UInt64(s)
        default: return nil
        }
    }

    private func describe(_ e: DBError) -> String {
        switch e {
        case .syntax(let n, _, let m): return "ERROR \(n): \(m)"
        case .network(let m, _): return "NETWORK: \(m)"
        case .auth(let m, _): return "AUTH: \(m)"
        case .timeout(let m): return "TIMEOUT: \(m)"
        case .cancelled: return "Cancelled"
        case .server(let n, _, let m): return "SERVER \(n): \(m)"
        case .constraint(let n, _, let m): return "CONSTRAINT \(n): \(m)"
        case .unknown(let m, _): return m
        }
    }
}

/// 无 PK 表 commit 前的二次确认参数（PRD §5.3.7.2）。
struct NoPKConfirmation: Equatable {
    let updates: Int
    let inserts: Int
    let deletes: Int
}
