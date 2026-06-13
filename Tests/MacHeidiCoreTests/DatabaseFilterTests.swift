import Testing
@testable import MacHeidiCore

@Suite("DatabaseFilter")
struct DatabaseFilterTests {

    let all = ["app_prod", "app_test", "information_schema", "mysql",
               "performance_schema", "sys", "wordpress"]

    @Test("Empty setting → hide system schemas")
    func emptyHidesSystem() {
        let r = DatabaseFilter.apply(all, defaultDatabases: "")
        #expect(r == ["app_prod", "app_test", "wordpress"])
    }

    @Test("Whitespace-only setting → hide system schemas")
    func whitespaceOnly() {
        let r = DatabaseFilter.apply(all, defaultDatabases: "   ")
        #expect(r == ["app_prod", "app_test", "wordpress"])
    }

    @Test("Single name → only that DB")
    func singleName() {
        let r = DatabaseFilter.apply(all, defaultDatabases: "app_prod")
        #expect(r == ["app_prod"])
    }

    @Test("Comma list → multiple DBs, preserves SHOW DATABASES order")
    func commaList() {
        let r = DatabaseFilter.apply(all, defaultDatabases: "wordpress, app_prod")
        #expect(r == ["app_prod", "wordpress"])
    }

    @Test("Case-insensitive match")
    func caseInsensitive() {
        let r = DatabaseFilter.apply(all, defaultDatabases: "APP_PROD")
        #expect(r == ["app_prod"])
    }

    @Test("Whitelist allows system schemas to show through")
    func allowsSystemSchemas() {
        let r = DatabaseFilter.apply(all, defaultDatabases: "mysql")
        #expect(r == ["mysql"])
    }

    @Test("Unknown name → empty (no error)")
    func unknownName() {
        let r = DatabaseFilter.apply(all, defaultDatabases: "does_not_exist")
        #expect(r.isEmpty)
    }

    @Test("Trailing comma / extra separators ignored")
    func trailingComma() {
        let r = DatabaseFilter.apply(all, defaultDatabases: "app_prod,,")
        #expect(r == ["app_prod"])
    }
}
