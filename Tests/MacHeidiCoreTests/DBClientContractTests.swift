import Testing
import Foundation
@testable import MacHeidiCore

/// Covers Feature: S5.1 DBClient 协议契约 (PRD §5.5.1, §5.5.7)
@Suite("S5.1 DBClient Contract")
struct DBClientContractTests {

    // MARK: 状态机

    @Test("新建的 client 处于 idle，connectionId 为 nil")
    func newClientIsIdle() async {
        let client = MockDBClient()
        let state = await client.state
        #expect(state == .idle)
        let cid = await client.connectionId
        #expect(cid == nil)
    }

    @Test("connect 成功后状态变为 connected 并暴露 connectionId")
    func connectSuccessTransitionsToConnected() async throws {
        let client = MockDBClient()
        await client.stubConnectSuccess(connectionId: 42)
        try await client.connect(.fixture())
        #expect(await client.state == .connected)
        #expect(await client.connectionId == 42)
    }

    @Test("connect 失败后状态保持 disconnected 并抛出 DBError")
    func connectFailureKeepsDisconnected() async {
        let client = MockDBClient()
        await client.stubConnectFailure(.auth(message: "bad pw", mysqlErrno: 1045))
        await #expect(throws: DBError.self) {
            try await client.connect(.fixture())
        }
        #expect(await client.state == .disconnected)
        #expect(await client.connectionId == nil)
    }

    @Test("disconnect 后状态变为 disconnected 并清空 connectionId")
    func disconnectClearsConnectionId() async throws {
        let client = MockDBClient()
        await client.stubConnectSuccess(connectionId: 7)
        try await client.connect(.fixture())
        await client.disconnect()
        #expect(await client.state == .disconnected)
        #expect(await client.connectionId == nil)
    }

    @Test("idle client 的 disconnect 是 no-op")
    func disconnectOnIdleIsNoOp() async {
        let client = MockDBClient()
        await client.disconnect()    // 不抛
        let s = await client.state
        #expect(s == .idle || s == .disconnected)
    }

    // MARK: 元数据查询

    @Test("listDatabases 在未连接时抛 .network")
    func listDatabasesRequiresConnection() async {
        let client = MockDBClient()
        await #expect(throws: DBError.self) {
            _ = try await client.listDatabases(includeSystem: false)
        }
    }

    @Test("listDatabases includeSystem=false 过滤掉系统库并按名排序")
    func listDatabasesFiltersSystemSchemas() async throws {
        let client = MockDBClient()
        await client.stubConnectSuccess(connectionId: 1)
        await client.stubDatabases(["sys", "app_prod", "mysql"])
        try await client.connect(.fixture())
        let result = try await client.listDatabases(includeSystem: false)
        #expect(result == ["app_prod"])
    }

    @Test("listDatabases includeSystem=true 包含系统库且整体按名排序")
    func listDatabasesIncludesSystemSchemasSorted() async throws {
        let client = MockDBClient()
        await client.stubConnectSuccess(connectionId: 1)
        await client.stubDatabases(
            ["sys", "app_prod", "mysql", "information_schema", "performance_schema"]
        )
        try await client.connect(.fixture())
        let result = try await client.listDatabases(includeSystem: true)
        #expect(result == ["app_prod", "information_schema", "mysql", "performance_schema", "sys"])
    }

    // MARK: query / exec

    @Test("query 在未连接时抛 .network")
    func queryRequiresConnection() async {
        let client = MockDBClient()
        await #expect(throws: DBError.self) {
            _ = try await client.query("SELECT 1")
        }
    }

    @Test("query 返回预先 stub 的 ResultSet")
    func queryReturnsStubbedResultSet() async throws {
        let client = MockDBClient()
        await client.stubConnectSuccess(connectionId: 1)
        let stub = ResultSet.fixture(rowCount: 2)
        await client.stubQuery("SELECT * FROM users", result: stub)
        try await client.connect(.fixture())
        let rs = try await client.query("SELECT * FROM users")
        #expect(rs.rows.count == 2)
    }

    @Test("exec 在未连接时抛 .network")
    func execRequiresConnection() async {
        let client = MockDBClient()
        await #expect(throws: DBError.self) {
            _ = try await client.exec("UPDATE users SET x=1")
        }
    }

    @Test("exec 返回预先 stub 的 ExecResult")
    func execReturnsStubbedExecResult() async throws {
        let client = MockDBClient()
        await client.stubConnectSuccess(connectionId: 1)
        await client.stubExec("UPDATE users SET x=1",
                              result: ExecResult(affectedRows: 3, lastInsertId: nil,
                                                 executionTime: .milliseconds(5), warnings: []))
        try await client.connect(.fixture())
        let r = try await client.exec("UPDATE users SET x=1")
        #expect(r.affectedRows == 3)
    }

    // MARK: cancel

    @Test("cancel 让 in-flight 的 query 以 .cancelled 抛出")
    func cancelInterruptsInFlightQuery() async throws {
        let client = MockDBClient()
        await client.stubConnectSuccess(connectionId: 1)
        try await client.connect(.fixture())
        // 安排一条"挂着等 cancel"的 query
        await client.stubCancellableQuery("SELECT SLEEP(10)")

        let task = Task<ResultSet, any Error> {
            try await client.query("SELECT SLEEP(10)")
        }
        // 让任务先跑起来再 cancel
        try await Task.sleep(for: .milliseconds(30))
        await client.cancel()

        await #expect(throws: DBError.self) {
            _ = try await task.value
        }
    }
}

// MARK: - Fixtures (intentionally co-located with tests; not shipped in prod target)

extension ConnectionConfig {
    static func fixture(
        hostname: String = "127.0.0.1",
        port: Int = 3306,
        user: String = "root",
        password: String = "password",
        defaultDatabase: String? = nil
    ) -> ConnectionConfig {
        ConnectionConfig(
            hostname: hostname, port: port, user: user, password: password,
            defaultDatabase: defaultDatabase, useSSL: false,
            connectTimeout: .seconds(10), queryTimeout: nil
        )
    }
}

extension ResultSet {
    static func fixture(rowCount: Int) -> ResultSet {
        let col = ColumnMeta(
            name: "id", mysqlType: "BIGINT", normalizedType: .int,
            nullable: false, defaultValue: nil, isAutoIncrement: true,
            isUnsigned: true, maxLength: nil, precision: nil, scale: nil, comment: ""
        )
        let rows = (0..<rowCount).map { i in [CellValue.int(Int64(i))] }
        return ResultSet(columns: [col], rows: rows,
                         executionTime: .milliseconds(1), warnings: [])
    }
}
