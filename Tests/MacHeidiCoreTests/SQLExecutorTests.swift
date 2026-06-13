import Testing
@testable import MacHeidiCore

@Suite("Multi-Statement Execution Pipeline S4.4/S4.5")
struct SQLExecutorTests {

    @Test("All succeed — outcomes match order")
    func allSuccess() async {
        let driver = SequentialSQLDriver(
            query: { _ in ResultSet(columns: [], rows: [], executionTime: .zero, warnings: []) },
            exec: { _ in ExecResult(affectedRows: 1, lastInsertId: nil, executionTime: .zero, warnings: []) }
        )
        let vm = await SQLExecutorViewModel(driver: driver)
        await MainActor.run { vm.sql = "SELECT 1; SELECT 2; UPDATE t SET x=1" }
        await vm.runAll()
        let n = await vm.outcomes.count
        #expect(n == 3)
    }

    @Test("Failure stops pipeline — no third outcome")
    func failureStops() async {
        // 第二条故意让 driver 抛错（用 SELECT 开头确保 classify=.query 走到 query 通道）
        let driver = SequentialSQLDriver(
            query: { sql in
                if sql.contains("BAD") {
                    struct QueryError: Error {}
                    throw QueryError()
                }
                return ResultSet(columns: [], rows: [], executionTime: .zero, warnings: [])
            },
            exec: { _ in
                ExecResult(affectedRows: 1, lastInsertId: nil, executionTime: .zero, warnings: [])
            }
        )
        let vm = await SQLExecutorViewModel(driver: driver)
        await MainActor.run { vm.sql = "SELECT 1; SELECT BAD; SELECT 3" }
        await vm.runAll()
        let outcomes = await vm.outcomes
        let n = outcomes.count
        #expect(n == 2, "expected 2 outcomes, got \(n)")
        if n >= 2 {
            if case .query = outcomes[0].kind {} else { Issue.record("first should be .query") }
            if case .error = outcomes[1].kind {} else { Issue.record("second should be .error") }
        }
    }

    @Test("Empty SQL produces zero outcomes")
    func emptySQL() async {
        let driver = SequentialSQLDriver.empty
        let vm = await SQLExecutorViewModel(driver: driver)
        await MainActor.run { vm.sql = ";;   ;" }
        await vm.runAll()
        #expect(await vm.outcomes.isEmpty == true)
    }

    @Test("Single query — one outcome")
    func singleQuery() async {
        let driver = SequentialSQLDriver.empty
        let vm = await SQLExecutorViewModel(driver: driver)
        await MainActor.run { vm.sql = "SELECT 1" }
        await vm.runAll()
        #expect(await vm.outcomes.count == 1)
    }

    @Test("Cursor + runCurrent — executes the statement under cursor")
    func runCurrent() async {
        let driver = SequentialSQLDriver.empty
        let vm = await SQLExecutorViewModel(driver: driver)
        await MainActor.run {
            vm.sql = "SELECT 1; SELECT 2; SELECT 3"
            vm.cursorOffset = 15  // "SELECT 2"
        }
        await vm.runCurrent()
        let s = await vm.outcomes.first?.sql.trimmingCharacters(in: .whitespaces) ?? ""
        #expect(s == "SELECT 2", "got '\(s)'")
    }
}

/// 视图模型：持有 SQL 文本 + 执行状态 + 结果序列。
///
/// @MainActor 因为所有写操作都是 UI 驱动的。driver 是 actor，await 时会离开 MainActor。
@MainActor
final class SQLExecutorViewModel<Driver: SQLQueryDriver> {
    let driver: Driver
    var sql = ""
    var outcomes: [QueryOutcome] = []
    var isRunning = false
    var cursorOffset: Int = 0

    init(driver: Driver) {
        self.driver = driver
    }

    /// F9：逐条执行所有语句，失败停止
    func runAll() async {
        isRunning = true
        defer { isRunning = false }
        outcomes.removeAll()
        let stmts = SQLSplitter.split(sql)
        for s in stmts {
            let kind = SQLSplitter.classify(s)
            do {
                if case .query = kind {
                    let rs = try await driver.query(s)
                    outcomes.append(QueryOutcome(sql: s, kind: .query(rs)))
                } else {
                    let r = try await driver.exec(s)
                    outcomes.append(QueryOutcome(sql: s, kind: .exec(r)))
                }
            } catch {
                outcomes.append(QueryOutcome(sql: s, kind: .error(error: String(describing: error))))
                break
            }
        }
    }

    /// Ctrl+Enter：只执行光标所在的那一条
    func runCurrent() async {
        isRunning = true
        defer { isRunning = false }
        outcomes.removeAll()
        guard let s = SQLSplitter.statementAtCursor(text: sql, offset: cursorOffset) else { return }
        let kind = SQLSplitter.classify(s)
        do {
            if case .query = kind {
                let rs = try await driver.query(s)
                outcomes.append(QueryOutcome(sql: s, kind: .query(rs)))
            } else {
                let r = try await driver.exec(s)
                outcomes.append(QueryOutcome(sql: s, kind: .exec(r)))
            }
        } catch {
            outcomes.append(QueryOutcome(sql: s, kind: .error(error: String(describing: error))))
        }
    }
}

/// DBClient 接口的迷你 protocol 副本 —— 为了做纯单元测试（不引入 MySQL driver）。
/// 真实实现层桥接到 DBClient。
public protocol SQLQueryDriver: Actor {
    func query(_ sql: String) async throws -> ResultSet
    func exec(_ sql: String) async throws -> ExecResult
}

actor SequentialSQLDriver: SQLQueryDriver {
    typealias QueryFn = @Sendable (String) async throws -> ResultSet
    typealias ExecFn = @Sendable (String) async throws -> ExecResult

    let queryFn: QueryFn
    let execFn: ExecFn

    init(query: @escaping QueryFn, exec: @escaping ExecFn) {
        self.queryFn = query
        self.execFn = exec
    }

    func query(_ sql: String) async throws -> ResultSet {
        try await queryFn(sql)
    }
    func exec(_ sql: String) async throws -> ExecResult {
        try await execFn(sql)
    }

    static var empty: SequentialSQLDriver {
        SequentialSQLDriver(
            query: { _ in ResultSet(columns: [], rows: [], executionTime: .zero, warnings: []) },
            exec: { _ in ExecResult(affectedRows: 0, lastInsertId: nil, executionTime: .zero, warnings: []) }
        )
    }
}

public struct QueryOutcomeForTest: Sendable {
    public let sql: String
    public let kind: Kind
    public enum Kind: Sendable {
        case query(ResultSet)
        case exec(ExecResult)
        case error(error: String)
    }
}
