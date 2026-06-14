import Foundation
import NIOCore
import NIOPosix
import Logging
import MySQLNIO
import MacHeidiCore

/// `DBClient` 的真实 MySQL 实现。
///
/// 包一层 MySQLNIO 的 `MySQLConnection`，把 EventLoopFuture 转 async/await，
/// 把 `MySQLError` 归一化为 ``DBError``（PRD §5.5.4）。
///
/// **线程模型**：Actor 串行所有调用（PRD §5.5.7）。NIO 的事件循环组在第一次
/// `connect` 时按需创建，整个进程共用一个，`shutdown` 在最后一个 client 释放时不显式关
/// （Foundation 推荐做法是让进程退出时随之关闭）。
public actor MySQLClient: DBClient {

    public private(set) var state: DBClientState = .idle
    public private(set) var connectionId: UInt64?

    /// 当前活跃连接；nil 表示未连接。
    private var connection: MySQLConnection?

    /// 当前配置缓存，cancel 时新开"杀手"连接需要它。
    private var lastConfig: ConnectionConfig?

    /// 静音 MySQLNIO 的日志；调用方关心的错误都会经 DBError 抛出。
    private static let logger: Logger = {
        var l = Logger(label: "macheidi.mysql")
        l.logLevel = .warning
        return l
    }()

    /// 整个进程共用一个 EventLoopGroup（MySQLNIO 推荐做法）。
    nonisolated(unsafe) private static var sharedGroup: EventLoopGroup?
    private static let groupLock = NSLock()
    private static func eventLoopGroup() -> any EventLoopGroup {
        groupLock.lock(); defer { groupLock.unlock() }
        if let g = sharedGroup { return g }
        let g = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        sharedGroup = g
        return g
    }

    public init() {}

    // MARK: DBClient

    public func connect(_ config: ConnectionConfig) async throws {
        state = .connecting
        lastConfig = config

        do {
            let conn = try await openConnection(config)
            connection = conn

            // 探测真实 connection id（CONNECTION_ID()）
            let rows = try await conn.simpleQuery("SELECT CONNECTION_ID()").get()
            if let v = rows.first?.values.first, let buf = v, let s = buf.getString(at: 0, length: buf.readableBytes) {
                connectionId = UInt64(s)
            }
            state = .connected
        } catch let err as DBError {
            connection = nil
            connectionId = nil
            state = .disconnected
            throw err
        } catch {
            connection = nil
            connectionId = nil
            state = .disconnected
            throw mapMySQLError(error)
        }
    }

    public func disconnect() async {
        if let conn = connection {
            _ = try? await conn.close().get()
        }
        connection = nil
        connectionId = nil
        state = .disconnected
    }

    public func listDatabases(includeSystem: Bool) async throws -> [String] {
        let rs = try await query("SHOW DATABASES")
        let names: [String] = rs.rows.compactMap {
            if case .string(let s) = $0.first { return s } else { return nil }
        }
        let filtered = includeSystem
            ? names
            : names.filter { !SystemSchemas.names.contains($0.lowercased()) }
        return filtered.sorted()
    }

    public func query(_ sql: String) async throws -> ResultSet {
        let conn = try requireConnection()
        let start = ContinuousClock.now
        do {
            let rows = try await conn.simpleQuery(sql).get()
            return makeResultSet(rows: rows, elapsed: ContinuousClock.now - start)
        } catch {
            throw mapMySQLError(error)
        }
    }

    public func exec(_ sql: String) async throws -> ExecResult {
        // simpleQuery 也能跑 DML/DDL；OK Packet 里有 affected rows，但 MySQLNIO 的
        // simpleQuery 把 OK 吞掉只返回 []，所以这里用 SELECT ROW_COUNT()/LAST_INSERT_ID()。
        let conn = try requireConnection()
        let start = ContinuousClock.now
        do {
            _ = try await conn.simpleQuery(sql).get()
            let meta = try await conn.simpleQuery(
                "SELECT ROW_COUNT() AS affected, LAST_INSERT_ID() AS lid"
            ).get()
            let affected: UInt64 = readUInt(meta.first?.values[0]) ?? 0
            let lid:     UInt64? = readUInt(meta.first?.values[1])
            return ExecResult(
                affectedRows: affected,
                lastInsertId: lid == 0 ? nil : lid,
                executionTime: ContinuousClock.now - start,
                warnings: []
            )
        } catch {
            throw mapMySQLError(error)
        }
    }

    public func cancel() async {
        // 关键：cancel() 是 actor 方法，但本 actor 当前正阻塞在 in-flight query 上。
        // 若 cancel() 内部 await openConnection()，会被排到 query 之后才执行 → 失效。
        //
        // 解决：把"开新连接 + 发 KILL"丢到一个独立的非 actor Task 里执行，
        // 只从 actor 取 cid+cfg 这两个状态值。
        guard let cid = connectionId, let cfg = lastConfig else { return }
        Task.detached {
            await Self.sendKillQuery(connectionId: cid, config: cfg)
        }
    }

    /// 在临时新连接上发 KILL QUERY；非 actor 上下文，不阻塞主连接。
    private static func sendKillQuery(connectionId cid: UInt64,
                                       config: ConnectionConfig) async {
        let group = eventLoopGroup()
        let addr: SocketAddress
        do {
            addr = try SocketAddress.makeAddressResolvingHost(config.hostname, port: config.port)
        } catch {
            return
        }
        let future = MySQLConnection.connect(
            to: addr, username: config.user, database: "",
            password: config.password,
            tlsConfiguration: config.useSSL ? .makeClientConfiguration() : nil,
            serverHostname: config.hostname,
            logger: logger,
            on: group.next()
        )
        guard let killer = try? await future.get() else { return }
        _ = try? await killer.simpleQuery("KILL QUERY \(cid)").get()
        _ = try? await killer.close().get()
    }

    // MARK: 私有

    private func requireConnection() throws -> MySQLConnection {
        guard let conn = connection, state == .connected else {
            throw DBError.network(message: "Not connected", underlying: nil)
        }
        return conn
    }

    private func openConnection(_ config: ConnectionConfig) async throws -> MySQLConnection {
        let group = Self.eventLoopGroup()
        let addr: SocketAddress
        do {
            addr = try SocketAddress.makeAddressResolvingHost(config.hostname, port: config.port)
        } catch {
            throw DBError.network(message: "Cannot resolve host: \(error)", underlying: error)
        }

        let future = MySQLConnection.connect(
            to: addr,
            username: config.user,
            database: config.defaultDatabase ?? "",
            password: config.password,
            tlsConfiguration: config.useSSL ? .makeClientConfiguration() : nil,
            serverHostname: config.hostname,
            logger: Self.logger,
            on: group.next()
        )

        // 手工超时；MySQLNIO 的 connect 没有 timeout 参数。
        let timeoutSeconds = Int(config.connectTimeout.components.seconds)
        return try await withTimeout(seconds: max(1, timeoutSeconds)) {
            do {
                return try await future.get()
            } catch {
                throw mapMySQLError(error)
            }
        }
    }

    private func makeResultSet(rows: [MySQLRow], elapsed: Duration) -> ResultSet {
        guard let first = rows.first else {
            return ResultSet(columns: [], rows: [], executionTime: elapsed, warnings: [])
        }
        let columns: [ColumnMeta] = first.columnDefinitions.map { def in
            ColumnMeta(
                name: def.name,
                mysqlType: mysqlTypeString(def),
                normalizedType: normalize(def.columnType, charset: def.characterSet),
                nullable: !def.flags.contains(.COLUMN_NOT_NULL),
                defaultValue: nil,
                isAutoIncrement: false,    // MySQLNIO 未暴露 AUTO_INCREMENT flag；
                                            // 后续通过 SHOW COLUMNS 单独探测（PRD §5.3.6）
                isUnsigned: def.flags.contains(.COLUMN_UNSIGNED),
                maxLength: Int(def.columnLength),
                precision: nil,
                scale: Int(def.decimals),
                comment: ""
            )
        }
        let mapped: [[CellValue]] = rows.map { row in
            zip(row.columnDefinitions, row.values).map { def, buf in
                makeCell(type: def.columnType, charset: def.characterSet,
                         buffer: buf, flags: def.flags)
            }
        }
        return ResultSet(columns: columns, rows: mapped, executionTime: elapsed, warnings: [])
    }

    /// 把 wire-protocol 的列定义映射到一个**人能看懂**的 mysqlType 字符串。
    /// 关键修正：`.blob` type code 在 wire 上同时表示 BLOB 与 TEXT，
    /// 靠 charset 区分（charset == 63 是 binary，即 BLOB；其余是 TEXT）。
    private func mysqlTypeString(_ def: MySQLProtocol.ColumnDefinition41) -> String {
        switch def.columnType {
        case .tinyBlob:
            return def.characterSet == .binary ? "tinyblob" : "tinytext"
        case .blob:
            return def.characterSet == .binary ? "blob" : "text"
        case .mediumBlob:
            return def.characterSet == .binary ? "mediumblob" : "mediumtext"
        case .longBlob:
            return def.characterSet == .binary ? "longblob" : "longtext"
        default:
            return String(describing: def.columnType)
        }
    }

    private func normalize(_ t: MySQLProtocol.DataType,
                           charset: MySQLProtocol.CharacterSet) -> NormalizedType {
        // MySQL wire 协议里 TEXT 列与 BLOB 共用 type code 0xfc，靠 column charset 区分：
        //   charset == 63 (binary) → 真二进制 BLOB
        //   其他 charset (utf8mb4 / latin1 / ...) → TEXT 系列，按 string 处理
        switch t {
        case .tiny, .short, .int24, .long: return .int
        case .longlong:                    return .int
        case .float, .double:              return .double
        case .decimal, .newdecimal:        return .decimal
        case .null:                        return .unknown
        case .timestamp, .datetime:        return .datetime
        case .date, .newdate, .year:       return .date
        case .time:                        return .time
        case .bit:                         return .uint
        case .json:                        return .json
        case .tinyBlob, .mediumBlob, .longBlob, .blob:
            return charset == .binary ? .blob : .string
        case .varchar, .varString, .string, .enum, .set:
            return .string
        default:
            return .unknown
        }
    }

    private func makeCell(type: MySQLProtocol.DataType,
                          charset: MySQLProtocol.CharacterSet,
                          buffer: ByteBuffer?,
                          flags: MySQLProtocol.ColumnFlags) -> CellValue {
        guard var buf = buffer, buf.readableBytes > 0 else { return .null }
        // simpleQuery 走的是 text protocol：所有值都是字符串。
        guard let s = buf.readString(length: buf.readableBytes) else { return .null }
        switch type {
        case .tiny, .short, .int24, .long, .longlong, .year:
            if flags.contains(.COLUMN_UNSIGNED), let u = UInt64(s) { return .uint(u) }
            return Int64(s).map { .int($0) } ?? .string(s)
        case .float, .double:
            return Double(s).map { .double($0) } ?? .string(s)
        case .decimal, .newdecimal:
            return .decimal(s)
        case .bit:
            return UInt64(s).map { .uint($0) } ?? .string(s)
        case .json:
            return .json(s)
        case .tinyBlob, .mediumBlob, .longBlob, .blob:
            // charset == 63 (binary) → 真 BLOB；其他 charset → TEXT 系列
            return charset == .binary ? .blob(Data(s.utf8)) : .string(s)
        default:
            return .string(s)
        }
    }

    private func readUInt(_ buffer: ByteBuffer??) -> UInt64? {
        guard var buf = buffer ?? nil, buf.readableBytes > 0,
              let s = buf.readString(length: buf.readableBytes) else { return nil }
        return UInt64(s)
    }
}

// MARK: - Timeout

private func withTimeout<T: Sendable>(
    seconds: Int,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw DBError.network(message: "Timeout after \(seconds)s", underlying: nil)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
