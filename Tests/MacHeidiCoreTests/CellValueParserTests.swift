import Testing
import Foundation
@testable import MacHeidiCore

@Suite("CellValueParser S3.6 type validation")
struct CellValueParserTests {

    // MARK: int / uint

    @Test("INT accepts a number")
    func intAccepts() throws {
        let col = ColumnMeta.int(name: "age", nullable: true)
        #expect(try CellValueParser.parse("42", column: col) == .int(42))
    }

    @Test("INT rejects non-numeric string")
    func intRejects() {
        let col = ColumnMeta.int(name: "age", nullable: true)
        #expect(throws: CellValueParseError.self) {
            _ = try CellValueParser.parse("abc", column: col)
        }
    }

    @Test("INT accepts negative")
    func intNegative() throws {
        let col = ColumnMeta.int(name: "delta", nullable: true)
        #expect(try CellValueParser.parse("-5", column: col) == .int(-5))
    }

    @Test("BIGINT UNSIGNED uses uint case")
    func bigintUnsigned() throws {
        let col = ColumnMeta(
            name: "id", mysqlType: "bigint unsigned",
            normalizedType: .int, nullable: false, defaultValue: nil,
            isAutoIncrement: false, isUnsigned: true,
            maxLength: nil, precision: nil, scale: nil, comment: ""
        )
        #expect(try CellValueParser.parse("18446744073709551610", column: col)
                == .uint(18446744073709551610))
    }

    // MARK: nullable

    @Test("Nullable column accepts NULL sentinel")
    func nullableAcceptsNull() throws {
        let col = ColumnMeta.varchar(name: "bio", nullable: true)
        #expect(try CellValueParser.parseNull(column: col) == .null)
    }

    @Test("NOT NULL column rejects NULL")
    func notNullRejects() {
        let col = ColumnMeta.varchar(name: "name", nullable: false)
        #expect(throws: CellValueParseError.self) {
            _ = try CellValueParser.parseNull(column: col)
        }
    }

    // MARK: bool / decimal

    @Test("TINYINT(1) parses as bool")
    func boolColumn() throws {
        let col = ColumnMeta(
            name: "active", mysqlType: "tinyint(1)",
            normalizedType: .bool, nullable: true, defaultValue: nil,
            isAutoIncrement: false, isUnsigned: false,
            maxLength: nil, precision: nil, scale: nil, comment: ""
        )
        #expect(try CellValueParser.parse("true", column: col) == .bool(true))
        #expect(try CellValueParser.parse("0", column: col) == .bool(false))
        #expect(try CellValueParser.parse("1", column: col) == .bool(true))
    }

    @Test("DECIMAL preserves precision as string")
    func decimalPreservesString() throws {
        let col = ColumnMeta(
            name: "price", mysqlType: "decimal(30,15)",
            normalizedType: .decimal, nullable: false, defaultValue: nil,
            isAutoIncrement: false, isUnsigned: false,
            maxLength: nil, precision: 30, scale: 15, comment: ""
        )
        #expect(try CellValueParser.parse("12345.678901234567890", column: col)
                == .decimal("12345.678901234567890"))
    }

    @Test("VARCHAR accepts any string")
    func varcharAccepts() throws {
        let col = ColumnMeta.varchar(name: "name", nullable: true)
        #expect(try CellValueParser.parse("Alice", column: col) == .string("Alice"))
        #expect(try CellValueParser.parse("", column: col) == .string(""))
    }

    // MARK: JSON / BLOB-as-JSON

    @Test("JSON column accepts valid JSON")
    func jsonAccepts() throws {
        let col = ColumnMeta(
            name: "payload", mysqlType: "json",
            normalizedType: .json, nullable: true, defaultValue: nil,
            isAutoIncrement: false, isUnsigned: false,
            maxLength: nil, precision: nil, scale: nil, comment: ""
        )
        #expect(try CellValueParser.parse(#"{"a":1}"#, column: col) == .json(#"{"a":1}"#))
    }

    @Test("JSON column rejects malformed JSON")
    func jsonRejects() {
        let col = ColumnMeta(
            name: "payload", mysqlType: "json",
            normalizedType: .json, nullable: true, defaultValue: nil,
            isAutoIncrement: false, isUnsigned: false,
            maxLength: nil, precision: nil, scale: nil, comment: ""
        )
        #expect(throws: CellValueParseError.self) {
            _ = try CellValueParser.parse("{invalid", column: col)
        }
    }

    @Test("BLOB column accepts JSON text → returns .blob with UTF-8 bytes")
    func blobAcceptsJSON() throws {
        let col = ColumnMeta.blob(name: "error_msg")
        let json = #"{"code":500,"msg":"oops"}"#
        let result = try CellValueParser.parse(json, column: col)
        #expect(result == .blob(Data(json.utf8)))
    }

    @Test("BLOB column rejects plain text (not JSON)")
    func blobRejectsPlainText() {
        let col = ColumnMeta.blob(name: "data")
        #expect(throws: CellValueParseError.self) {
            _ = try CellValueParser.parse("hello world", column: col)
        }
    }

    @Test("BLOB column rejects bare number")
    func blobRejectsBareNumber() {
        let col = ColumnMeta.blob(name: "data")
        #expect(throws: CellValueParseError.self) {
            _ = try CellValueParser.parse("42", column: col)
        }
    }
}

// MARK: - Convenience fixtures used across tests

extension ColumnMeta {
    static func int(name: String, nullable: Bool, isUnsigned: Bool = false) -> ColumnMeta {
        ColumnMeta(
            name: name, mysqlType: "int", normalizedType: .int,
            nullable: nullable, defaultValue: nil, isAutoIncrement: false,
            isUnsigned: isUnsigned, maxLength: nil, precision: nil, scale: nil, comment: ""
        )
    }
    static func varchar(name: String, nullable: Bool, maxLength: Int = 255) -> ColumnMeta {
        ColumnMeta(
            name: name, mysqlType: "varchar(\(maxLength))", normalizedType: .string,
            nullable: nullable, defaultValue: nil, isAutoIncrement: false,
            isUnsigned: false, maxLength: maxLength, precision: nil, scale: nil, comment: ""
        )
    }
    static func text(name: String, nullable: Bool = true) -> ColumnMeta {
        ColumnMeta(
            name: name, mysqlType: "text", normalizedType: .string,
            nullable: nullable, defaultValue: nil, isAutoIncrement: false,
            isUnsigned: false, maxLength: 65535, precision: nil, scale: nil, comment: ""
        )
    }
    static func blob(name: String, nullable: Bool = true) -> ColumnMeta {
        ColumnMeta(
            name: name, mysqlType: "blob", normalizedType: .blob,
            nullable: nullable, defaultValue: nil, isAutoIncrement: false,
            isUnsigned: false, maxLength: nil, precision: nil, scale: nil, comment: ""
        )
    }
}
