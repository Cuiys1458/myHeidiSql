import Testing
@testable import MacHeidiCore

@Suite("RefreshPolicy S2.6")
struct RefreshPolicyTests {

    @Test("Nothing selected → refresh databases")
    func noneFallback() {
        #expect(RefreshPolicy.target(for: .none) == .sessionDatabases)
    }

    @Test("Session selected → refresh databases")
    func sessionRefreshes() {
        #expect(RefreshPolicy.target(for: .session) == .sessionDatabases)
    }

    @Test("Database selected → refresh that database's tables")
    func dbRefreshesItself() {
        #expect(RefreshPolicy.target(for: .database("app")) == .databaseTables("app"))
    }

    @Test("Table selected → refresh parent database")
    func tableRefreshesParent() {
        let r = RefreshPolicy.target(for: .table(database: "app", table: "users"))
        #expect(r == .databaseTables("app"))
    }

    @Test("View selected → refresh parent database")
    func viewRefreshesParent() {
        let r = RefreshPolicy.target(for: .view(database: "app", view: "v_active"))
        #expect(r == .databaseTables("app"))
    }
}
