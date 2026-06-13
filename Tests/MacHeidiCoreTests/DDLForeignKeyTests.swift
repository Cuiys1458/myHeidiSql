import Testing
@testable import MacHeidiCore

@Suite("DDLGenerator — foreign keys & table options")
struct DDLForeignKeyTests {

    @Test("Simple FK: orders.user_id → users.id")
    func simpleFK() throws {
        let sql = try DDLGenerator.addForeignKey(
            database: "db", table: "orders",
            fk: DDLGenerator.ForeignKeySpec(
                name: "fk_user",
                columns: ["user_id"],
                refTable: "users", refColumns: ["id"]
            )
        )
        #expect(sql.contains("ADD CONSTRAINT `fk_user`"))
        #expect(sql.contains("FOREIGN KEY (`user_id`)"))
        #expect(sql.contains("REFERENCES `users` (`id`)"))
        #expect(sql.contains("ON DELETE NO ACTION"))
        #expect(sql.contains("ON UPDATE NO ACTION"))
    }

    @Test("FK with cross-database ref")
    func crossDb() throws {
        let sql = try DDLGenerator.addForeignKey(
            database: "db", table: "orders",
            fk: DDLGenerator.ForeignKeySpec(
                name: "fk_u", columns: ["user_id"],
                refDatabase: "auth_db", refTable: "users", refColumns: ["id"]
            )
        )
        #expect(sql.contains("REFERENCES `auth_db`.`users` (`id`)"))
    }

    @Test("FK with CASCADE actions")
    func cascade() throws {
        let sql = try DDLGenerator.addForeignKey(
            database: "db", table: "orders",
            fk: DDLGenerator.ForeignKeySpec(
                name: "fk", columns: ["user_id"],
                refTable: "users", refColumns: ["id"],
                onDelete: .cascade, onUpdate: .setNull
            )
        )
        #expect(sql.contains("ON DELETE CASCADE"))
        #expect(sql.contains("ON UPDATE SET NULL"))
    }

    @Test("FK composite columns")
    func composite() throws {
        let sql = try DDLGenerator.addForeignKey(
            database: "db", table: "tx",
            fk: DDLGenerator.ForeignKeySpec(
                name: "fk_x", columns: ["tenant_id", "user_id"],
                refTable: "users", refColumns: ["tenant_id", "id"]
            )
        )
        #expect(sql.contains("(`tenant_id`, `user_id`)"))
        #expect(sql.contains("(`tenant_id`, `id`)"))
    }

    @Test("FK empty name rejected")
    func emptyName() {
        #expect(throws: DDLGeneratorError.self) {
            _ = try DDLGenerator.addForeignKey(
                database: "db", table: "t",
                fk: DDLGenerator.ForeignKeySpec(
                    name: "", columns: ["c"], refTable: "r", refColumns: ["id"]
                )
            )
        }
    }

    @Test("FK empty columns rejected")
    func emptyCols() {
        #expect(throws: DDLGeneratorError.self) {
            _ = try DDLGenerator.addForeignKey(
                database: "db", table: "t",
                fk: DDLGenerator.ForeignKeySpec(
                    name: "fk", columns: [], refTable: "r", refColumns: ["id"]
                )
            )
        }
    }

    @Test("Drop FK")
    func dropFK() throws {
        let sql = try DDLGenerator.dropForeignKey(
            database: "db", table: "orders", name: "fk_user"
        )
        #expect(sql == "ALTER TABLE `db`.`orders` DROP FOREIGN KEY `fk_user`")
    }

    @Test("Set ENGINE only")
    func engineOnly() throws {
        let sql = try DDLGenerator.setTableOptions(
            database: "db", table: "t", engine: "InnoDB"
        )
        #expect(sql == "ALTER TABLE `db`.`t` ENGINE=InnoDB")
    }

    @Test("Set ENGINE + CHARSET + COMMENT")
    func multipleOptions() throws {
        let sql = try DDLGenerator.setTableOptions(
            database: "db", table: "t",
            engine: "InnoDB", charset: "utf8mb4", comment: "my table"
        )
        #expect(sql?.contains("ENGINE=InnoDB") == true)
        #expect(sql?.contains("DEFAULT CHARSET=utf8mb4") == true)
        #expect(sql?.contains("COMMENT='my table'") == true)
    }

    @Test("All-empty options return nil")
    func emptyOptionsNil() throws {
        let sql = try DDLGenerator.setTableOptions(database: "db", table: "t")
        #expect(sql == nil)
    }

    @Test("Comment escapes single quote")
    func commentEscape() throws {
        let sql = try DDLGenerator.setTableOptions(
            database: "db", table: "t", comment: "it's"
        )
        #expect(sql?.contains("'it''s'") == true)
    }

    @Test("Rename table")
    func renameTable() throws {
        let sql = try DDLGenerator.renameTable(
            database: "db", table: "old", newName: "new"
        )
        #expect(sql == "RENAME TABLE `db`.`old` TO `db`.`new`")
    }
}
