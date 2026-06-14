import Testing
import Foundation
@testable import MacHeidiMySQL
import MacHeidiCore

/// Covers Feature: S5.2 MySQL 驱动集成
///
/// 这些是**集成测试**，需要真实 MySQL 8 在 127.0.0.1:3306（PRD §13 R1/R5）。
/// 若实例不可达整组 skip，不算失败 —— CI/无 MySQL 的机器不会误报。
@Suite("S5.2 MySQL Integration", .enabled(if: MySQLIntegration.isReachable))
struct MySQLIntegrationTests {

    // MARK: 连接

    @Test("能用凭据建立连接，connectionId 与 CONNECTION_ID() 一致")
    func connectAndConnectionIdMatchesServer() async throws {
        let client = MySQLClient()
        try await client.connect(MySQLIntegration.validConfig)
        let cid = await client.connectionId
        #expect(cid != nil)

        let rs = try await client.query("SELECT CONNECTION_ID()")
        guard case .uint(let serverCid) = rs.rows[0][0] else {
            // 服务端可能返回 .int 或 .uint，两者都接受
            if case .int(let i) = rs.rows[0][0] {
                #expect(UInt64(i) == cid)
                await client.disconnect()
                return
            }
            Issue.record("Unexpected cell type: \(rs.rows[0][0])")
            return
        }
        #expect(serverCid == cid)
        await client.disconnect()
    }

    @Test("错误密码抛 .auth(1045)")
    func wrongPasswordAuthError() async {
        let client = MySQLClient()
        var cfg = MySQLIntegration.validConfig
        cfg = ConnectionConfig(
            hostname: cfg.hostname, port: cfg.port, user: cfg.user,
            password: "definitely-wrong-pw-\(UUID().uuidString)",
            defaultDatabase: nil, useSSL: false,
            connectTimeout: .seconds(5), queryTimeout: nil
        )
        do {
            try await client.connect(cfg)
            Issue.record("Expected throw")
        } catch let err as DBError {
            guard case .auth(_, let errno) = err else {
                Issue.record("Expected .auth, got \(err)")
                return
            }
            #expect(errno == 1045)
        } catch {
            Issue.record("Expected DBError, got \(error)")
        }
    }

    @Test("不存在的 host 在超时内抛 .network")
    func unreachableHostNetworkError() async {
        let client = MySQLClient()
        // TEST-NET-1 不可达。NIO 的 connect 会等到 OS 层 TCP 超时（默认 ~75s on Darwin），
        // MySQLClient.withTimeout 兜底；并发跑测试时受调度影响实际可能略晚于 timeout，
        // 这里给个宽松的 12 秒上限避免 swift-testing 并发跑时偶发失败。
        let cfg = ConnectionConfig(
            hostname: "192.0.2.1", port: 3306, user: "root", password: "",
            defaultDatabase: nil, useSSL: false,
            connectTimeout: .seconds(3), queryTimeout: nil
        )
        let start = ContinuousClock.now
        do {
            try await client.connect(cfg)
            Issue.record("Expected throw")
        } catch let err as DBError {
            #expect(err.isNetwork)
            #expect(ContinuousClock.now - start < .seconds(12))
        } catch {
            Issue.record("Expected DBError, got \(error)")
        }
    }

    // MARK: 元数据

    @Test("listDatabases 排除系统库")
    func listDatabasesExcludesSystem() async throws {
        let client = try await MySQLIntegration.connected()
        defer { Task { await client.disconnect() } }

        let dbs = try await client.listDatabases(includeSystem: false)
        #expect(!dbs.isEmpty)
        for sys in ["information_schema", "performance_schema", "mysql", "sys"] {
            #expect(!dbs.contains(sys), "\(sys) should be filtered")
        }
    }

    // MARK: 查询

    @Test("query 返回 ResultSet")
    func querySimpleSelect() async throws {
        let client = try await MySQLIntegration.connected()
        defer { Task { await client.disconnect() } }

        let rs = try await client.query("SELECT 1 AS one, 'hi' AS greet")
        #expect(rs.columns.count == 2)
        #expect(rs.columns[0].name == "one")
        #expect(rs.columns[1].name == "greet")
        #expect(rs.rows.count == 1)
    }

    @Test("语法错抛 .syntax(1064)")
    func syntaxErrorMapsCorrectly() async throws {
        let client = try await MySQLIntegration.connected()
        defer { Task { await client.disconnect() } }

        do {
            _ = try await client.query("SELEKT 1")
            Issue.record("Expected throw")
        } catch let err as DBError {
            guard case .syntax(let errno, _, _) = err else {
                Issue.record("Expected .syntax, got \(err)")
                return
            }
            #expect(errno == 1064)
        }
    }

    @Test("exec 返回 affectedRows")
    func execAffectedRowsForTempTable() async throws {
        let client = try await MySQLIntegration.connected()
        defer { Task { await client.disconnect() } }

        let suffix = UUID().uuidString.prefix(8).lowercased()
        let table  = "macheidi_test_\(suffix)"

        // 准备临时表
        _ = try await client.exec("CREATE DATABASE IF NOT EXISTS macheidi_test")
        _ = try await client.exec("""
            CREATE TABLE macheidi_test.\(table) (id INT, val INT)
            """)
        defer {
            Task { _ = try? await client.exec("DROP TABLE macheidi_test.\(table)") }
        }
        _ = try await client.exec(
            "INSERT INTO macheidi_test.\(table) VALUES (1,1),(2,2),(3,3)"
        )
        let r = try await client.exec(
            "UPDATE macheidi_test.\(table) SET val = val + 1"
        )
        #expect(r.affectedRows == 3)
    }

    @Test("KILL QUERY 让 in-flight 查询提前结束")
    func cancelKillsRunningQuery() async throws {
        let client = try await MySQLIntegration.connected()
        defer { Task { await client.disconnect() } }

        // MySQL 特性：SLEEP() 被 KILL QUERY 中断时返回 1（而不是抛错）。
        // 因此判定 cancel 是否生效用"提前结束"作为信号，而不是异常类型。
        // 普通 SELECT/DML 在被 KILL 时则会抛 1317 (errno) → DBError.cancelled。
        let start = ContinuousClock.now
        let task = Task<ResultSet, any Error> {
            try await client.query("SELECT SLEEP(8)")
        }
        try await Task.sleep(for: .seconds(1))
        await client.cancel()

        do {
            let rs = try await task.value
            let elapsed = ContinuousClock.now - start
            #expect(elapsed < .seconds(4),
                    "KILL should interrupt SLEEP(8) within 4s, took \(elapsed)")
            // 被 KILL 的 SLEEP 返回单行单列值 1
            if case .int(let v) = rs.rows.first?.first {
                #expect(v == 1, "Killed SLEEP should return 1")
            }
        } catch let err as DBError {
            // 也接受抛 cancelled / network 的情况（不同 MySQL 版本行为可能差异）
            let elapsed = ContinuousClock.now - start
            #expect(elapsed < .seconds(4), "Threw \(err) too late: \(elapsed)")
        }
    }

    @Test("disconnect 后能重新 connect")
    func reconnectAfterDisconnect() async throws {
        let client = MySQLClient()
        try await client.connect(MySQLIntegration.validConfig)
        let cid1 = await client.connectionId
        await client.disconnect()

        try await client.connect(MySQLIntegration.validConfig)
        let cid2 = await client.connectionId
        #expect(cid2 != nil)
        #expect(cid2 != cid1)
        await client.disconnect()
    }
}

// MARK: - Integration env helpers

enum MySQLIntegration {

    /// 默认指向 PRD §test-db 的本地实例；通过环境变量可改。
    static let validConfig = ConnectionConfig(
        hostname: ProcessInfo.processInfo.environment["MACHEIDI_TEST_HOST"] ?? "127.0.0.1",
        port: Int(ProcessInfo.processInfo.environment["MACHEIDI_TEST_PORT"] ?? "3306") ?? 3306,
        user: ProcessInfo.processInfo.environment["MACHEIDI_TEST_USER"] ?? "root",
        password: ProcessInfo.processInfo.environment["MACHEIDI_TEST_PASS"] ?? "password",
        defaultDatabase: nil, useSSL: false,
        connectTimeout: .seconds(5), queryTimeout: nil
    )

    /// 同步 TCP probe；用于 `@Suite(.enabled(if:))`。Suite-level gate 必须同步。
    static let isReachable: Bool = probeReachable()

    private static func probeReachable() -> Bool {
        let host = validConfig.hostname
        let port = validConfig.port
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        let ok = host.withCString { cstr in inet_pton(AF_INET, cstr, &addr.sin_addr) == 1 }
        guard ok else { return false }

        // non-blocking + select for short timeout
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                connect(sock, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var write_fds = fd_set()
        fdSet(sock, set: &write_fds)
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        let s = select(sock + 1, nil, &write_fds, nil, &tv)
        guard s > 0 else { return false }

        var soErr: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(sock, SOL_SOCKET, SO_ERROR, &soErr, &len)
        return soErr == 0
    }

    /// 一次性 connect 给共用。
    static func connected() async throws -> MySQLClient {
        let c = MySQLClient()
        try await c.connect(validConfig)
        return c
    }
}

/// Swift-friendly FD_SET helper (Foundation doesn't expose macros).
private func fdSet(_ fd: Int32, set: inout fd_set) {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
    let mask: Int32 = 1 << bitOffset
    withUnsafeMutablePointer(to: &set.fds_bits) {
        $0.withMemoryRebound(to: Int32.self, capacity: 32) { p in
            p[intOffset] = p[intOffset] | mask
        }
    }
}

private extension DBError {
    var isNetwork: Bool { if case .network = self { return true } else { return false } }
}
