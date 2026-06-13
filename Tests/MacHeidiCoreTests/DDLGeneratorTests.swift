import Testing
@testable import MacHeidiCore

@Suite("DDLGenerator — column operations")
struct DDLGeneratorTests {

    private let dbName = "db"
    private let tableName = "users"

    private func existing() -> [ColumnMeta] {
        [
            ColumnMeta.int(name: "id", nullable: false),
            ColumnMeta.varchar(name: "name", nullable: false),
            ColumnMeta.varchar(name: "email", nullable: true),
        ]
    }

    // MARK: ADD

    @Test("Add minimal INT column")
    func addInt() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .add(
                column: ColumnSpec(name: "age", mysqlType: "INT"),
                position: nil
            )
        )
        #expect(r.sql == "ALTER TABLE `db`.`users` ADD COLUMN `age` INT NULL")
    }

    @Test("Add NOT NULL with DEFAULT")
    func addNotNullDefault() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .add(
                column: ColumnSpec(
                    name: "status", mysqlType: "VARCHAR(20)",
                    nullable: false, defaultLiteral: "'active'"
                ),
                position: nil
            )
        )
        #expect(r.sql.contains("ADD COLUMN `status` VARCHAR(20) NOT NULL DEFAULT 'active'"))
    }

    @Test("Add AUTO_INCREMENT PK")
    func addAutoIncPK() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: [], currentPrimaryKey: [],
            operation: .add(
                column: ColumnSpec(
                    name: "id", mysqlType: "BIGINT UNSIGNED",
                    nullable: false, isAutoIncrement: true, isPrimaryKey: true
                ),
                position: nil
            )
        )
        #expect(r.sql.contains("`id` BIGINT UNSIGNED NOT NULL"))
        #expect(r.sql.contains("AUTO_INCREMENT"))
        #expect(r.sql.contains("PRIMARY KEY"))
    }

    @Test("Backtick in column name escaped")
    func backtickEscaped() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .add(
                column: ColumnSpec(name: "weird`name", mysqlType: "INT"),
                position: nil
            )
        )
        #expect(r.sql.contains("`weird``name`"))
    }

    @Test("AFTER position")
    func afterPosition() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .add(
                column: ColumnSpec(name: "age", mysqlType: "INT"),
                position: .after("name")
            )
        )
        #expect(r.sql.hasSuffix("AFTER `name`"))
    }

    @Test("FIRST position")
    func firstPosition() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .add(
                column: ColumnSpec(name: "id2", mysqlType: "INT"),
                position: .first
            )
        )
        #expect(r.sql.hasSuffix(" FIRST"))
    }

    // MARK: DROP

    @Test("Drop column")
    func dropCol() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .drop(name: "email")
        )
        #expect(r.sql == "ALTER TABLE `db`.`users` DROP COLUMN `email`")
    }

    @Test("Drop PK column → warning but not error")
    func dropPKWarns() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .drop(name: "id")
        )
        #expect(r.sql == "ALTER TABLE `db`.`users` DROP COLUMN `id`")
        #expect(r.warnings.contains { $0.contains("PRIMARY KEY") })
    }

    // MARK: MODIFY

    @Test("Modify type")
    func modifyType() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .modify(
                name: "id",
                newSpec: ColumnSpec(name: "id", mysqlType: "BIGINT", nullable: false)
            )
        )
        #expect(r.sql == "ALTER TABLE `db`.`users` MODIFY COLUMN `id` BIGINT NOT NULL")
    }

    @Test("Modify nullability")
    func modifyNullable() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .modify(
                name: "name",
                newSpec: ColumnSpec(name: "name", mysqlType: "VARCHAR(50)",
                                     nullable: true)
            )
        )
        #expect(r.sql.contains("MODIFY COLUMN `name` VARCHAR(50) NULL"))
    }

    // MARK: RENAME

    @Test("Rename only")
    func renameOnly() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .rename(
                oldName: "name",
                newSpec: ColumnSpec(name: "full_name", mysqlType: "VARCHAR(100)")
            )
        )
        #expect(r.sql == "ALTER TABLE `db`.`users` CHANGE COLUMN `name` `full_name` VARCHAR(100) NULL")
    }

    @Test("Rename + modify type + nullability")
    func renameAndModify() throws {
        let r = try DDLGenerator.alter(
            database: dbName, table: tableName,
            currentColumns: existing(), currentPrimaryKey: ["id"],
            operation: .rename(
                oldName: "id",
                newSpec: ColumnSpec(name: "user_id", mysqlType: "SMALLINT", nullable: false)
            )
        )
        #expect(r.sql.contains("CHANGE COLUMN `id` `user_id` SMALLINT NOT NULL"))
    }

    // MARK: validation

    @Test("Duplicate name rejected")
    func dupRejected() {
        #expect(throws: DDLGeneratorError.self) {
            _ = try DDLGenerator.alter(
                database: dbName, table: tableName,
                currentColumns: existing(), currentPrimaryKey: ["id"],
                operation: .add(
                    column: ColumnSpec(name: "email", mysqlType: "INT"),
                    position: nil
                )
            )
        }
    }

    @Test("Modify nonexistent rejected")
    func nonexistentRejected() {
        #expect(throws: DDLGeneratorError.self) {
            _ = try DDLGenerator.alter(
                database: dbName, table: tableName,
                currentColumns: existing(), currentPrimaryKey: ["id"],
                operation: .modify(
                    name: "nope",
                    newSpec: ColumnSpec(name: "nope", mysqlType: "INT")
                )
            )
        }
    }

    @Test("Empty name rejected")
    func emptyNameRejected() {
        #expect(throws: DDLGeneratorError.self) {
            _ = try DDLGenerator.alter(
                database: dbName, table: tableName,
                currentColumns: existing(), currentPrimaryKey: ["id"],
                operation: .add(
                    column: ColumnSpec(name: "", mysqlType: "INT"),
                    position: nil
                )
            )
        }
    }
}
