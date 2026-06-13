import Testing
import Foundation
@testable import MacHeidiCore

@Suite("SQLGenerator S3.6 / S3.8 / S3.9")
struct SQLGeneratorTests {

    let dbName = "macheidi_test"
    let tableName = "users"

    private func tableWithPK() -> TableSchema {
        TableSchema(
            columns: [
                ColumnMeta.int(name: "id", nullable: false),
                ColumnMeta.varchar(name: "name", nullable: false),
                ColumnMeta.int(name: "age", nullable: true),
            ],
            primaryKey: ["id"],
            indices: []
        )
    }
    private func noPKTable() -> TableSchema {
        TableSchema(
            columns: [
                ColumnMeta.int(name: "a", nullable: true),
                ColumnMeta.varchar(name: "b", nullable: true),
                ColumnMeta.int(name: "c", nullable: true),
            ],
            primaryKey: [],
            indices: []
        )
    }
    private func noPKTableWithText() -> TableSchema {
        TableSchema(
            columns: [
                ColumnMeta.int(name: "a", nullable: true),
                ColumnMeta.text(name: "bio"),
                ColumnMeta.blob(name: "avatar"),
            ],
            primaryKey: [],
            indices: []
        )
    }

    // MARK: UPDATE with PK

    @Test("UPDATE with single-column PK")
    func updateWithPK() throws {
        let schema = tableWithPK()
        let sql = try SQLGenerator.update(
            database: dbName, table: tableName, schema: schema,
            originalRow: [.int(1), .string("Alice"), .int(30)],
            changedColumns: ["name": .string("Bob")]
        )
        #expect(sql == "UPDATE `macheidi_test`.`users` SET `name` = 'Bob' WHERE `id` = 1")
    }

    @Test("UPDATE multiple columns at once")
    func updateMultipleColumns() throws {
        let schema = tableWithPK()
        let sql = try SQLGenerator.update(
            database: dbName, table: tableName, schema: schema,
            originalRow: [.int(1), .string("Alice"), .int(30)],
            changedColumns: ["name": .string("Bob"), "age": .int(31)]
        )
        // 列顺序与 schema 一致（保持稳定）
        #expect(sql.contains("`name` = 'Bob'"))
        #expect(sql.contains("`age` = 31"))
        #expect(sql.contains("WHERE `id` = 1"))
    }

    @Test("UPDATE with composite PK")
    func updateCompositePK() throws {
        let schema = TableSchema(
            columns: [
                ColumnMeta.int(name: "tenant_id", nullable: false),
                ColumnMeta.int(name: "user_id", nullable: false),
                ColumnMeta.varchar(name: "name", nullable: true),
            ],
            primaryKey: ["tenant_id", "user_id"],
            indices: []
        )
        let sql = try SQLGenerator.update(
            database: "db", table: "ut", schema: schema,
            originalRow: [.int(5), .int(10), .string("Alice")],
            changedColumns: ["name": .string("Bob")]
        )
        #expect(sql.contains("WHERE `tenant_id` = 5 AND `user_id` = 10"))
    }

    @Test("UPDATE escapes single-quote in string value")
    func updateEscapesQuote() throws {
        let schema = tableWithPK()
        let sql = try SQLGenerator.update(
            database: dbName, table: tableName, schema: schema,
            originalRow: [.int(1), .string("Alice"), .int(30)],
            changedColumns: ["name": .string("it's")]
        )
        #expect(sql.contains("'it''s'"))
    }

    @Test("UPDATE SET to NULL produces 'col = NULL'")
    func updateSetNull() throws {
        let schema = tableWithPK()
        let sql = try SQLGenerator.update(
            database: dbName, table: tableName, schema: schema,
            originalRow: [.int(1), .string("Alice"), .int(30)],
            changedColumns: ["age": .null]
        )
        #expect(sql.contains("`age` = NULL"))
    }

    // MARK: UPDATE without PK (R4)

    @Test("No-PK UPDATE uses all columns with NULL-safe equal in WHERE")
    func noPKUpdateUsesAllColumns() throws {
        let schema = noPKTable()
        let sql = try SQLGenerator.update(
            database: dbName, table: "no_pk", schema: schema,
            originalRow: [.int(1), .string("x"), .null],
            changedColumns: ["a": .int(2)]
        )
        #expect(sql.contains("WHERE `a` <=> 1 AND `b` <=> 'x' AND `c` <=> NULL"))
    }

    @Test("No-PK UPDATE excludes BLOB / TEXT from WHERE")
    func noPKExcludesBlobText() throws {
        let schema = noPKTableWithText()
        let result = try SQLGenerator.updateWithDiagnostics(
            database: dbName, table: "x", schema: schema,
            originalRow: [.int(1), .string("hello"), .blob(Data())],
            changedColumns: ["a": .int(2)]
        )
        #expect(!result.sql.contains("`bio`"))
        #expect(!result.sql.contains("`avatar`"))
        #expect(result.warnings.contains { $0.contains("BLOB/TEXT") })
    }

    @Test("No-PK refuses commit when editing BLOB/TEXT itself")
    func noPKRefuseEditOnExcludedColumn() {
        let schema = noPKTableWithText()
        #expect(throws: SQLGeneratorError.self) {
            _ = try SQLGenerator.update(
                database: dbName, table: "x", schema: schema,
                originalRow: [.int(1), .string("old"), .blob(Data())],
                changedColumns: ["bio": .string("new")]
            )
        }
    }

    // MARK: INSERT

    @Test("INSERT only sends user-set columns")
    func insertOnlyUserSet() throws {
        let schema = TableSchema(
            columns: [
                ColumnMeta(name: "id", mysqlType: "bigint", normalizedType: .int,
                           nullable: false, defaultValue: nil, isAutoIncrement: true,
                           isUnsigned: true, maxLength: nil, precision: nil, scale: nil, comment: ""),
                ColumnMeta.varchar(name: "name", nullable: false),
                ColumnMeta.int(name: "age", nullable: true),
            ],
            primaryKey: ["id"],
            indices: []
        )
        let sql = try SQLGenerator.insert(
            database: dbName, table: tableName, schema: schema,
            values: ["name": .string("Alice")]
        )
        #expect(sql == "INSERT INTO `macheidi_test`.`users` (`name`) VALUES ('Alice')")
    }

    @Test("INSERT with NULL value")
    func insertNullValue() throws {
        let schema = tableWithPK()
        let sql = try SQLGenerator.insert(
            database: dbName, table: tableName, schema: schema,
            values: ["name": .string("Bob"), "age": .null]
        )
        #expect(sql.contains("VALUES ('Bob', NULL)") || sql.contains("VALUES (NULL, 'Bob')"))
    }

    @Test("Empty INSERT throws (caller should skip)")
    func emptyInsertThrows() {
        let schema = tableWithPK()
        #expect(throws: SQLGeneratorError.self) {
            _ = try SQLGenerator.insert(
                database: dbName, table: tableName, schema: schema,
                values: [:]
            )
        }
    }

    // MARK: DELETE

    @Test("DELETE with PK")
    func deleteWithPK() throws {
        let schema = tableWithPK()
        let sql = try SQLGenerator.delete(
            database: dbName, table: tableName, schema: schema,
            originalRow: [.int(42), .string("X"), .null]
        )
        #expect(sql == "DELETE FROM `macheidi_test`.`users` WHERE `id` = 42")
    }

    @Test("DELETE without PK uses all columns")
    func deleteNoPK() throws {
        let schema = noPKTable()
        let sql = try SQLGenerator.delete(
            database: dbName, table: "no_pk", schema: schema,
            originalRow: [.int(1), .string("x"), .null]
        )
        #expect(sql.contains("WHERE `a` <=> 1 AND `b` <=> 'x' AND `c` <=> NULL"))
    }

    // MARK: literal escaping

    @Test("Literal: int / uint / double / decimal / null / string")
    func literalCases() {
        #expect(SQLGenerator.literal(.int(42)) == "42")
        #expect(SQLGenerator.literal(.uint(42)) == "42")
        #expect(SQLGenerator.literal(.double(1.5)) == "1.5")
        #expect(SQLGenerator.literal(.decimal("123.45")) == "123.45")
        #expect(SQLGenerator.literal(.null) == "NULL")
        #expect(SQLGenerator.literal(.string("hi")) == "'hi'")
        #expect(SQLGenerator.literal(.string("it's")) == "'it''s'")
        #expect(SQLGenerator.literal(.bool(true)) == "1")
        #expect(SQLGenerator.literal(.bool(false)) == "0")
    }
}
