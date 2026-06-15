import Testing
@testable import MacHeidiCore

@Suite("CSV Table Inferrer — auto CREATE TABLE from CSV")
struct CSVTableInferrerTests {

    @Test("Numeric column → BIGINT")
    func bigintInference() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["count"],
            rows: [["10"], ["100"], ["1000"]]
        )
        #expect(spec.columns[0].mysqlType == "BIGINT")
        #expect(!spec.columns[0].nullable)
    }

    @Test("Decimal column → DECIMAL(20,6)")
    func decimalInference() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["price"],
            rows: [["1.5"], ["100.99"], ["0.001"]]
        )
        #expect(spec.columns[0].mysqlType == "DECIMAL(20,6)")
    }

    @Test("ISO date column → DATE")
    func dateInference() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["birthday"],
            rows: [["2020-01-15"], ["2021-12-31"], ["1999-06-30"]]
        )
        #expect(spec.columns[0].mysqlType == "DATE")
    }

    @Test("Datetime column → DATETIME")
    func datetimeInference() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["created"],
            rows: [
                ["2026-06-15 10:30:00"],
                ["2026-06-15 10:31:23"],
                ["2026-06-15T11:00:00"],
            ]
        )
        #expect(spec.columns[0].mysqlType == "DATETIME")
    }

    @Test("Empty cell → nullable")
    func emptyMakesNullable() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["maybe"],
            rows: [["10"], [""], ["30"]]
        )
        #expect(spec.columns[0].nullable)
        #expect(spec.columns[0].mysqlType == "BIGINT")
    }

    @Test("Mixed text → VARCHAR with rounded length")
    func varcharInference() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["name"],
            rows: [["Alice"], ["Bob"], ["Charlie Brown"]]
        )
        #expect(spec.columns[0].mysqlType.hasPrefix("VARCHAR("))
    }

    @Test("Long text → TEXT")
    func textInference() throws {
        let long = String(repeating: "a", count: 250)
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["bio"],
            rows: [[long], [long], [long]]
        )
        #expect(spec.columns[0].mysqlType == "TEXT")
    }

    @Test("Column name cleaning — non-alphanumeric replaced")
    func columnNameCleaning() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["First Name", "User-ID", "性别"],
            rows: [["a", "1", "F"]]
        )
        #expect(spec.columns[0].cleanName == "First_Name")
        #expect(spec.columns[1].cleanName == "User_ID")
        #expect(spec.columns[2].cleanName == "性别")
    }

    @Test("Column starting with digit → prefixed col_")
    func numericStartName() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["123abc"],
            rows: [["x"]]
        )
        #expect(spec.columns[0].cleanName.hasPrefix("col_"))
    }

    @Test("CREATE TABLE has implicit id PRIMARY KEY")
    func includesIdPK() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["name"],
            rows: [["a"]]
        )
        #expect(spec.createSQL.contains("`id` BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY"))
        #expect(spec.createSQL.contains("ENGINE=InnoDB"))
        #expect(spec.primaryKeyColumn == nil)
        #expect(spec.pkIsAutoIncrement == true)
    }

    @Test("CSV with own 'id' column → that column becomes PK (no implicit id)")
    func csvIdBecomesPK() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["id", "name"],
            rows: [
                ["uuid-1", "a"],
                ["uuid-2", "b"],
            ]
        )
        // 不应该重复 id 列
        let idCount = spec.createSQL.components(separatedBy: "`id`").count - 1
        #expect(idCount == 1, "id should appear exactly once in CREATE TABLE")
        // CSV 自带 id → 不是 AUTO_INCREMENT
        #expect(!spec.createSQL.contains("AUTO_INCREMENT"))
        #expect(spec.createSQL.contains("`id` VARCHAR"))
        #expect(spec.createSQL.contains("PRIMARY KEY"))
        #expect(spec.primaryKeyColumn == "id")
        #expect(spec.pkIsAutoIncrement == false)
    }

    @Test("CSV id column is case-insensitive ('ID' / 'Id' also count)")
    func csvIdCaseInsensitive() throws {
        let spec = try CSVTableInferrer.infer(
            database: "db", table: "t",
            headers: ["ID", "name"],
            rows: [["1", "a"]]
        )
        let idCount = spec.createSQL.components(separatedBy: "`ID`").count - 1
        #expect(idCount == 1)
        #expect(!spec.createSQL.contains("AUTO_INCREMENT"))
    }
}
