import Foundation

/// 内存版 ``DBClient``，供单元测试与上层 ViewModel 测试使用。
///
/// 不做任何真实 IO；行为完全由 `stub*` 方法注入。
/// 测试在 `MacHeidiCoreTests` 中通过 `@testable` 直接使用此类型。
public actor MockDBClient: DBClient {

    public private(set) var state: DBClientState = .idle
    public private(set) var connectionId: UInt64?

    // MARK: stubs

    private enum ConnectOutcome {
        case success(connectionId: UInt64)
        case failure(DBError)
    }

    private var connectOutcome: ConnectOutcome?
    private var databases: [String] = []
    private var queryStubs: [String: ResultSet] = [:]
    private var execStubs: [String: ExecResult] = [:]
    private var cancellableQueries: Set<String> = []
    private var cancelRequested: Bool = false

    public init() {}

    // MARK: 测试注入接口

    public func stubConnectSuccess(connectionId: UInt64) {
        self.connectOutcome = .success(connectionId: connectionId)
    }

    public func stubConnectFailure(_ error: DBError) {
        self.connectOutcome = .failure(error)
    }

    public func stubDatabases(_ names: [String]) {
        self.databases = names
    }

    public func stubQuery(_ sql: String, result: ResultSet) {
        queryStubs[sql] = result
    }

    public func stubExec(_ sql: String, result: ExecResult) {
        execStubs[sql] = result
    }

    /// 安排一条 query 在收到 cancel 后以 `.cancelled` 抛出。
    public func stubCancellableQuery(_ sql: String) {
        cancellableQueries.insert(sql)
    }

    // MARK: DBClient

    public func connect(_ config: ConnectionConfig) async throws {
        state = .connecting
        switch connectOutcome {
        case .success(let cid):
            connectionId = cid
            state = .connected
        case .failure(let err):
            connectionId = nil
            state = .disconnected
            throw err
        case .none:
            // 未设 stub 时默认成功，cid = 1
            connectionId = 1
            state = .connected
        }
    }

    public func disconnect() async {
        connectionId = nil
        state = .disconnected
    }

    public func listDatabases(includeSystem: Bool) async throws -> [String] {
        try requireConnected()
        let filtered = includeSystem
            ? databases
            : databases.filter { !SystemSchemas.names.contains($0.lowercased()) }
        return filtered.sorted()
    }

    public func query(_ sql: String) async throws -> ResultSet {
        try requireConnected()

        if cancellableQueries.contains(sql) {
            // 模拟"挂起等 cancel"
            let start = ContinuousClock.now
            while !cancelRequested {
                if ContinuousClock.now - start > .seconds(5) {
                    throw DBError.timeout(message: "Mock cancellable query never cancelled")
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            cancelRequested = false  // 一次性
            throw DBError.cancelled
        }

        guard let rs = queryStubs[sql] else {
            throw DBError.server(mysqlErrno: -1, sqlState: "MOCK",
                                 message: "No query stub for: \(sql)")
        }
        return rs
    }

    public func exec(_ sql: String) async throws -> ExecResult {
        try requireConnected()
        guard let r = execStubs[sql] else {
            throw DBError.server(mysqlErrno: -1, sqlState: "MOCK",
                                 message: "No exec stub for: \(sql)")
        }
        return r
    }

    public func cancel() async {
        cancelRequested = true
    }

    // MARK: helpers

    private func requireConnected() throws {
        guard state == .connected else {
            throw DBError.network(message: "Not connected", underlying: nil)
        }
    }
}
