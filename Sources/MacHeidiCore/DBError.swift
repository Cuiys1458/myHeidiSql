import Foundation

/// 上层（UI / ViewModel）唯一感知的数据库错误类型。
///
/// 任何来自 driver / 网络栈 / 系统的错误都必须先通过 ``normalize(_:)`` 归类到这个枚举，
/// UI 按 case 选择反馈样式（PRD §5.5.4.3）。
public enum DBError: Error, Sendable {

    /// 连不上、网络断开、DNS 失败、超时（TCP 层）。
    case network(message: String, underlying: (any Error)?)

    /// 认证失败、库不存在、权限不足。
    case auth(message: String, mysqlErrno: Int?)

    /// SQL 语法/语义错（错列、错表、关键字错）。
    case syntax(mysqlErrno: Int, sqlState: String, message: String)

    /// 约束冲突（PK / FK / UNIQUE / CHECK）。
    case constraint(mysqlErrno: Int, sqlState: String, message: String)

    /// 锁等待 / 语句执行超时。
    case timeout(message: String)

    /// 用户主动 Cancel 触发的中断（MySQL 1317）。
    case cancelled

    /// 其他 MySQL 服务端错（read-only、磁盘满等），保留 errno 供 UI 显示。
    case server(mysqlErrno: Int, sqlState: String, message: String)

    /// 非 MySQL 错（Swift 网络栈、Codable、未知）。
    case unknown(message: String, underlying: (any Error)?)
}

extension DBError: Equatable {
    public static func == (lhs: DBError, rhs: DBError) -> Bool {
        switch (lhs, rhs) {
        case (.network(let a, _), .network(let b, _)):
            return a == b
        case (.auth(let m1, let e1), .auth(let m2, let e2)):
            return m1 == m2 && e1 == e2
        case (.syntax(let e1, let s1, let m1), .syntax(let e2, let s2, let m2)):
            return e1 == e2 && s1 == s2 && m1 == m2
        case (.constraint(let e1, let s1, let m1), .constraint(let e2, let s2, let m2)):
            return e1 == e2 && s1 == s2 && m1 == m2
        case (.timeout(let a), .timeout(let b)):
            return a == b
        case (.cancelled, .cancelled):
            return true
        case (.server(let e1, let s1, let m1), .server(let e2, let s2, let m2)):
            return e1 == e2 && s1 == s2 && m1 == m2
        case (.unknown(let a, _), .unknown(let b, _)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Normalization

/// MySQL driver 抛出的原始错误信息，由 driver 适配层包装后传给归一化函数。
///
/// 这是 `MacHeidiCore` 唯一不依赖具体 MySQL 驱动的"原始错误"载体；
/// 真正的 driver（MySQLNIO 等）在 `MacHeidiMySQL` 模块里把自家错误转成这个结构。
public struct MySQLRawError: Error, Sendable, Equatable {
    public let errno: Int
    public let sqlState: String
    public let message: String

    public init(errno: Int, sqlState: String, message: String) {
        self.errno = errno
        self.sqlState = sqlState
        self.message = message
    }
}

extension DBError {

    /// 把任意 `Error` 归一化为 ``DBError``。
    ///
    /// - 已是 ``DBError``：原样返回（幂等）。
    /// - ``MySQLRawError``：按 PRD §5.5.4.2 的 errno 映射表分类。
    /// - 其他 ``Error``：归类为 ``DBError/unknown(message:underlying:)``。
    public static func normalize(_ error: any Error) -> DBError {
        if let already = error as? DBError {
            return already
        }
        if let raw = error as? MySQLRawError {
            return classify(raw)
        }
        let description = String(describing: error)
        return .unknown(message: description, underlying: error)
    }

    /// errno → case 映射（PRD §5.5.4.2）。集中在一处便于审计与扩展。
    private static func classify(_ raw: MySQLRawError) -> DBError {
        switch raw.errno {
        // —— 网络
        case 2002, 2003, 2005, 2013:
            return .network(message: raw.message, underlying: raw)

        // —— 认证 / 库访问
        case 1044, 1045, 1049:
            return .auth(message: raw.message, mysqlErrno: raw.errno)

        // —— 语法 / 语义
        case 1064, 1054, 1146:
            return .syntax(mysqlErrno: raw.errno, sqlState: raw.sqlState, message: raw.message)

        // —— 约束
        case 1062, 1451, 1452:
            return .constraint(mysqlErrno: raw.errno, sqlState: raw.sqlState, message: raw.message)

        // —— Cancel
        case 1317:
            return .cancelled

        // —— 超时
        case 1205:
            return .timeout(message: raw.message)

        // —— 兜底：其他都归 server
        default:
            return .server(mysqlErrno: raw.errno, sqlState: raw.sqlState, message: raw.message)
        }
    }
}
