import Foundation

/// MySQL 标识符（库名/表名/列名）引号和转义。
///
/// 唯一允许的字符是所有非 NUL 字符；反引号用两个反引号转义（MySQL 规范）。
///
/// 参考：https://dev.mysql.com/doc/refman/8.0/en/identifiers.html
public enum SQLIdentifierError: Error, Equatable {
    case empty
    case containsNul
}

public enum SQLIdentifier {

    /// 按 MySQL 规范将标识符用反引号包裹并转义。
    public static func quote(_ name: String) throws -> String {
        guard !name.isEmpty else { throw SQLIdentifierError.empty }
        guard !name.contains("\u{0000}") else { throw SQLIdentifierError.containsNul }
        let escaped = name.replacingOccurrences(of: "`", with: "``")
        return "`\(escaped)`"
    }

    /// 生成限定名：`db`.`table`。
    public static func qualified(database: String, table: String) throws -> String {
        let qdb = try quote(database)
        let qtb = try quote(table)
        return "\(qdb).\(qtb)"
    }
}

/// 会话删除前置检查（PRD §S1.5）。
public enum SessionDeletionPolicy {

    public enum Result: Equatable {
        case allowed
        case blocked(reason: String)
    }

    /// 删除前评估是否允许。
    public static func evaluate(sessionId: UUID, activeSessionId: UUID?) -> Result {
        guard let active = activeSessionId else {
            return .allowed
        }
        guard sessionId != active else {
            return .blocked(reason: "Disconnect this session before deleting it.")
        }
        return .allowed
    }
}
