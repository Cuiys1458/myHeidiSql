import Testing
import Foundation
@testable import MacHeidiCore

@Suite("ResultExporter")
struct ResultExporterTests {

    private func makeRS() -> ResultSet {
        let cols = [
            ColumnMeta.int(name: "id", nullable: false),
            ColumnMeta.varchar(name: "name", nullable: false),
            ColumnMeta.varchar(name: "note", nullable: true),
        ]
        let rows: [[CellValue]] = [
            [.int(1), .string("Alice"), .null],
            [.int(2), .string("Bob, the \"hero\""), .string("line1\nline2")],
            [.int(3), .string("Carol"), .string("ok")],
        ]
        return ResultSet(columns: cols, rows: rows, executionTime: .zero, warnings: [])
    }

    @Test("CSV header + rows + RFC4180 escaping")
    func csv() {
        let s = ResultExporter.toCSV(makeRS())
        #expect(s.contains("id,name,note\n"))
        // null → empty
        #expect(s.contains("1,Alice,\n"))
        // quote 双写 + 含逗号包裹
        #expect(s.contains("\"Bob, the \"\"hero\"\"\""))
        // 含换行的字段被引号包裹
        #expect(s.contains("\"line1\nline2\""))
    }

    @Test("TSV uses tabs")
    func tsv() {
        let s = ResultExporter.toTSV(makeRS())
        #expect(s.contains("id\tname\tnote\n"))
        #expect(s.contains("1\tAlice\t\n"))
    }

    @Test("SQL produces INSERT for each row")
    func sql() {
        let s = ResultExporter.toSQL(makeRS(), database: "db", table: "t")
        // 3 条 INSERT 语句（按 ; 数量算，避免多行字段引起的 newline 误判）
        let inserts = s.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        #expect(inserts.count == 3)
        #expect(s.contains("INSERT INTO `db`.`t` (`id`, `name`, `note`) VALUES (1, 'Alice', NULL);"))
        #expect(s.contains("'Bob, the \"hero\"'"))
    }

    @Test("Empty result set → comment")
    func empty() {
        let rs = ResultSet(columns: [], rows: [], executionTime: .zero, warnings: [])
        #expect(ResultExporter.toSQL(rs, database: "d", table: "t").contains("empty"))
    }
}
