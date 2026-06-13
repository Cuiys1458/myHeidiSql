import Testing
import Foundation
@testable import MacHeidiCore

/// Covers Feature: S5.4 错误归一化 (PRD §5.5.4)
@Suite("S5.4 Error Normalization")
struct ErrorNormalizationTests {

    // MARK: Network errors (连接阶段)

    @Test("MySQL errno 2003 (Can't connect) maps to .network")
    func cantConnectMapsToNetwork() {
        let raw = MySQLRawError(errno: 2003, sqlState: "HY000",
                                message: "Can't connect to MySQL server on '127.0.0.1' (61)")
        let normalized = DBError.normalize(raw)
        guard case .network(let message, _) = normalized else {
            Issue.record("Expected .network, got \(normalized)")
            return
        }
        #expect(message.contains("Can't connect"))
    }

    @Test("MySQL errno 2005 (Unknown host) maps to .network")
    func unknownHostMapsToNetwork() {
        let raw = MySQLRawError(errno: 2005, sqlState: "HY000",
                                message: "Unknown MySQL server host")
        #expect(DBError.normalize(raw).isNetwork)
    }

    @Test("MySQL errno 2013 (Lost connection) maps to .network")
    func lostConnectionMapsToNetwork() {
        let raw = MySQLRawError(errno: 2013, sqlState: "HY000",
                                message: "Lost connection to MySQL server during query")
        #expect(DBError.normalize(raw).isNetwork)
    }

    // MARK: Auth errors

    @Test("MySQL errno 1045 (Access denied) maps to .auth and preserves errno")
    func accessDeniedMapsToAuth() {
        let raw = MySQLRawError(errno: 1045, sqlState: "28000",
                                message: "Access denied for user 'root'@'localhost'")
        let normalized = DBError.normalize(raw)
        guard case .auth(_, let errno) = normalized else {
            Issue.record("Expected .auth, got \(normalized)")
            return
        }
        #expect(errno == 1045)
    }

    @Test("MySQL errno 1049 (Unknown database) maps to .auth")
    func unknownDatabaseMapsToAuth() {
        let raw = MySQLRawError(errno: 1049, sqlState: "42000",
                                message: "Unknown database 'foo'")
        #expect(DBError.normalize(raw).isAuth)
    }

    // MARK: Syntax errors

    @Test("MySQL errno 1064 (Syntax) maps to .syntax with errno and sqlstate")
    func syntaxErrorPreservesMetadata() {
        let raw = MySQLRawError(errno: 1064, sqlState: "42000",
                                message: "You have an error in your SQL syntax")
        let normalized = DBError.normalize(raw)
        guard case .syntax(let errno, let sqlState, _) = normalized else {
            Issue.record("Expected .syntax, got \(normalized)")
            return
        }
        #expect(errno == 1064)
        #expect(sqlState == "42000")
    }

    @Test("MySQL errno 1054 (Unknown column) maps to .syntax")
    func unknownColumnMapsToSyntax() {
        let raw = MySQLRawError(errno: 1054, sqlState: "42S22",
                                message: "Unknown column 'foo' in 'field list'")
        #expect(DBError.normalize(raw).isSyntax)
    }

    @Test("MySQL errno 1146 (Unknown table) maps to .syntax")
    func unknownTableMapsToSyntax() {
        let raw = MySQLRawError(errno: 1146, sqlState: "42S02",
                                message: "Table 'foo.bar' doesn't exist")
        #expect(DBError.normalize(raw).isSyntax)
    }

    // MARK: Constraint errors

    @Test("MySQL errno 1062 (Duplicate key) maps to .constraint with errno")
    func duplicateKeyMapsToConstraint() {
        let raw = MySQLRawError(errno: 1062, sqlState: "23000",
                                message: "Duplicate entry '1' for key 'PRIMARY'")
        let normalized = DBError.normalize(raw)
        guard case .constraint(let errno, _, _) = normalized else {
            Issue.record("Expected .constraint, got \(normalized)")
            return
        }
        #expect(errno == 1062)
    }

    @Test("MySQL errno 1452 (FK fails) maps to .constraint")
    func fkConstraintMapsToConstraint() {
        let raw = MySQLRawError(errno: 1452, sqlState: "23000",
                                message: "Cannot add or update a child row")
        #expect(DBError.normalize(raw).isConstraint)
    }

    @Test("MySQL errno 1451 (FK referenced) maps to .constraint")
    func fkReferencedMapsToConstraint() {
        let raw = MySQLRawError(errno: 1451, sqlState: "23000",
                                message: "Cannot delete or update a parent row")
        #expect(DBError.normalize(raw).isConstraint)
    }

    // MARK: Cancel

    @Test("MySQL errno 1317 (Query interrupted) maps to .cancelled")
    func interruptedMapsToCancelled() {
        let raw = MySQLRawError(errno: 1317, sqlState: "70100",
                                message: "Query execution was interrupted")
        if case .cancelled = DBError.normalize(raw) { return }
        Issue.record("Expected .cancelled, got \(DBError.normalize(raw))")
    }

    // MARK: Timeout

    @Test("MySQL errno 1205 (Lock wait timeout) maps to .timeout")
    func lockWaitMapsToTimeout() {
        let raw = MySQLRawError(errno: 1205, sqlState: "HY000",
                                message: "Lock wait timeout exceeded")
        if case .timeout = DBError.normalize(raw) { return }
        Issue.record("Expected .timeout, got \(DBError.normalize(raw))")
    }

    // MARK: Server fallback

    @Test("Unmapped MySQL errno falls back to .server preserving errno")
    func unmappedFallsToServer() {
        let raw = MySQLRawError(errno: 1290, sqlState: "HY000",
                                message: "The MySQL server is running with the --read-only option")
        let normalized = DBError.normalize(raw)
        guard case .server(let errno, _, _) = normalized else {
            Issue.record("Expected .server, got \(normalized)")
            return
        }
        #expect(errno == 1290)
    }

    // MARK: Unknown / non-MySQL errors

    @Test("Non-MySQL error (URLError) maps to .unknown preserving description")
    func nonMySQLMapsToUnknown() {
        struct DummyURLError: Error, CustomStringConvertible {
            var description: String { "The Internet connection appears to be offline." }
        }
        let normalized = DBError.normalize(DummyURLError())
        guard case .unknown(let message, _) = normalized else {
            Issue.record("Expected .unknown, got \(normalized)")
            return
        }
        #expect(message.contains("Internet connection"))
    }
}

// MARK: - Test helpers (intentionally tiny; live with the tests, not the prod target)

private extension DBError {
    var isNetwork: Bool { if case .network = self { return true } else { return false } }
    var isAuth: Bool { if case .auth = self { return true } else { return false } }
    var isSyntax: Bool { if case .syntax = self { return true } else { return false } }
    var isConstraint: Bool { if case .constraint = self { return true } else { return false } }
}
