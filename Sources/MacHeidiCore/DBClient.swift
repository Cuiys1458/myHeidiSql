import Foundation

// MARK: - DBClient 协议（PRD §5.5.1）

/// 上层（ViewModel / UI / 集成测试）唯一感知的数据库客户端协议。
///
/// 真实实现（MySQLNIO 适配）与测试替身（MockDBClient）都必须遵守这套契约。
/// `Actor` 确保串行执行 —— 同一时刻一个连接只跑一条查询（PRD §5.5.7）。
public protocol DBClient: Actor {

    /// 当前协议连接的 MySQL `CONNECTION_ID()`；连接前为 `nil`。
    var connectionId: UInt64? { get }

    /// 当前连接状态。
    var state: DBClientState { get }

    /// 建立 TCP + 协议握手 + USE default db（若指定）。
    func connect(_ config: ConnectionConfig) async throws

    /// 优雅关闭；若已断开则 no-op，不抛。
    func disconnect() async

    /// `SHOW DATABASES` 包装；`includeSystem=false` 时过滤掉
    /// `information_schema / performance_schema / mysql / sys`；结果按名升序。
    func listDatabases(includeSystem: Bool) async throws -> [String]

    /// 仅用于 SELECT-like 语句；返回完整内存 `ResultSet`。
    func query(_ sql: String) async throws -> ResultSet

    /// 用于 DML / DDL；返回影响行数与耗时。
    func exec(_ sql: String) async throws -> ExecResult

    /// 在**另一条新连接**上发 `KILL QUERY <connectionId>`，不抢占主连接。
    /// 主连接上 in-flight 的 query/exec 会以 `DBError.cancelled` 抛出。
    func cancel() async
}

// MARK: - 状态机（PRD §5.5.1）

public enum DBClientState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case disconnected
}

// MARK: - 连接配置

public struct ConnectionConfig: Sendable, Equatable {
    public let hostname: String
    public let port: Int
    public let user: String
    public let password: String        // 明文，从 Keychain 取，仅在内存
    public let defaultDatabase: String?
    public let useSSL: Bool
    public let connectTimeout: Duration
    public let queryTimeout: Duration?

    public init(
        hostname: String,
        port: Int,
        user: String,
        password: String,
        defaultDatabase: String?,
        useSSL: Bool,
        connectTimeout: Duration,
        queryTimeout: Duration?
    ) {
        self.hostname = hostname
        self.port = port
        self.user = user
        self.password = password
        self.defaultDatabase = defaultDatabase
        self.useSSL = useSSL
        self.connectTimeout = connectTimeout
        self.queryTimeout = queryTimeout
    }
}

// MARK: - 系统库白名单

/// 默认从 `listDatabases` 结果中剔除的系统库（PRD §5.5.1.listDatabases）。
public enum SystemSchemas {
    public static let names: Set<String> = [
        "information_schema",
        "performance_schema",
        "mysql",
        "sys",
    ]
}
