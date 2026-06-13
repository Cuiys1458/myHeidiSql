import Testing
@testable import MacHeidiCore

@Suite("DDLGenerator — index operations")
struct DDLIndexGeneratorTests {

    // MARK: ADD

    @Test("Single-column INDEX")
    func single() throws {
        let sql = try DDLGenerator.addIndex(
            database: "db", table: "users",
            indexName: "idx_email", columns: ["email"], unique: false
        )
        #expect(sql == "ALTER TABLE `db`.`users` ADD INDEX `idx_email` (`email`)")
    }

    @Test("UNIQUE INDEX")
    func unique() throws {
        let sql = try DDLGenerator.addIndex(
            database: "db", table: "users",
            indexName: "uniq_email", columns: ["email"], unique: true
        )
        #expect(sql == "ALTER TABLE `db`.`users` ADD UNIQUE INDEX `uniq_email` (`email`)")
    }

    @Test("Composite INDEX")
    func composite() throws {
        let sql = try DDLGenerator.addIndex(
            database: "db", table: "users",
            indexName: "idx_status_created",
            columns: ["status", "created_at"], unique: false
        )
        #expect(sql.contains("(`status`, `created_at`)"))
    }

    @Test("Empty index name rejected")
    func emptyIdxName() {
        #expect(throws: DDLGeneratorError.self) {
            _ = try DDLGenerator.addIndex(
                database: "db", table: "t", indexName: "", columns: ["c"], unique: false
            )
        }
    }

    @Test("Empty columns rejected")
    func emptyCols() {
        #expect(throws: DDLGeneratorError.self) {
            _ = try DDLGenerator.addIndex(
                database: "db", table: "t", indexName: "x", columns: [], unique: false
            )
        }
    }

    @Test("All-whitespace columns rejected")
    func whitespaceCols() {
        #expect(throws: DDLGeneratorError.self) {
            _ = try DDLGenerator.addIndex(
                database: "db", table: "t", indexName: "x", columns: ["", "  "], unique: false
            )
        }
    }

    @Test("Backtick in name escaped")
    func backtickEscape() throws {
        let sql = try DDLGenerator.addIndex(
            database: "db", table: "t",
            indexName: "idx`weird", columns: ["col`name"], unique: false
        )
        #expect(sql.contains("`idx``weird`"))
        #expect(sql.contains("`col``name`"))
    }

    // MARK: DROP

    @Test("Drop normal index")
    func drop() throws {
        let sql = try DDLGenerator.dropIndex(
            database: "db", table: "users", indexName: "idx_email"
        )
        #expect(sql == "ALTER TABLE `db`.`users` DROP INDEX `idx_email`")
    }

    @Test("Drop PRIMARY → DROP PRIMARY KEY")
    func dropPrimary() throws {
        let sql = try DDLGenerator.dropIndex(
            database: "db", table: "users", indexName: "PRIMARY"
        )
        #expect(sql == "ALTER TABLE `db`.`users` DROP PRIMARY KEY")
    }

    @Test("Lowercase 'primary' also matches")
    func dropPrimaryLowercase() throws {
        let sql = try DDLGenerator.dropIndex(
            database: "db", table: "users", indexName: "primary"
        )
        #expect(sql.contains("DROP PRIMARY KEY"))
    }

    @Test("Empty name rejected")
    func dropEmpty() {
        #expect(throws: DDLGeneratorError.self) {
            _ = try DDLGenerator.dropIndex(database: "db", table: "t", indexName: "")
        }
    }
}
