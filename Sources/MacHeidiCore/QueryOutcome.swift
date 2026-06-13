import Foundation

/// 一条 SQL 语句的执行结果。
public struct QueryOutcome: Sendable {
    public let sql: String
    public let kind: Kind
    public init(sql: String, kind: Kind) {
        self.sql = sql
        self.kind = kind
    }

    public enum Kind: Sendable {
        case query(ResultSet)
        case exec(ExecResult)
        case error(error: String)
    }
}
