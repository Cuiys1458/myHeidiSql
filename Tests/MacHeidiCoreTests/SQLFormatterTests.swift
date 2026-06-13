import Testing
@testable import MacHeidiCore

@Suite("SQLFormatter")
struct SQLFormatterTests {

    @Test("Keywords uppercased")
    func upper() {
        let r = SQLFormatter.format("select * from users")
        #expect(r.contains("SELECT"))
        #expect(r.contains("FROM"))
        #expect(r.lowercased().contains("users"))
    }

    @Test("FROM on new line")
    func fromOnNewLine() {
        let r = SQLFormatter.format("select id from users")
        #expect(r.contains("\nFROM\n"))
    }

    @Test("WHERE on new line")
    func whereOnNewLine() {
        let r = SQLFormatter.format("select id from users where id = 1")
        #expect(r.contains("\nWHERE\n"))
    }

    @Test("AND indented under WHERE")
    func andIndented() {
        let r = SQLFormatter.format("select id from users where a = 1 and b = 2")
        #expect(r.contains("\n  AND "))
    }

    @Test("ORDER BY kept together")
    func orderBy() {
        let r = SQLFormatter.format("select id from users order by name")
        #expect(r.contains("ORDER BY"))
    }

    @Test("Strings preserved with their case")
    func stringPreserved() {
        let r = SQLFormatter.format("select 'hello WORLD' from users")
        #expect(r.contains("'hello WORLD'"))
    }

    @Test("Backtick identifiers untouched")
    func backtickPreserved() {
        let r = SQLFormatter.format("select `User_ID` from users")
        #expect(r.contains("`User_ID`"))
    }

    @Test("Block comment preserved")
    func blockComment() {
        let r = SQLFormatter.format("select /* skip */ * from t")
        #expect(r.contains("/* skip */"))
    }

    @Test("Trailing semicolon preserved")
    func trailingSemi() {
        let r = SQLFormatter.format("select 1;")
        #expect(r.hasSuffix(";"))
    }
}
