import Testing
import Foundation
@testable import MacHeidiCore

@Suite("UserPreferences")
struct UserPreferencesTests {

    private func makeIsolatedPrefs() -> (UserPreferences, UserDefaults) {
        let suite = "test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return (UserPreferences(defaults: d), d)
    }

    @Test("Default page size is 100 when never set")
    func defaultPageSize() {
        let (p, _) = makeIsolatedPrefs()
        #expect(p.pageSize == 100)
    }

    @Test("Page size persists round-trip")
    func pageSizeRoundtrip() {
        let (p, _) = makeIsolatedPrefs()
        p.pageSize = 500
        #expect(p.pageSize == 500)
    }

    @Test("Zero page size falls back to default")
    func zeroFallsBackToDefault() {
        let (p, d) = makeIsolatedPrefs()
        d.set(0, forKey: "macheidi.pref.pageSize")
        #expect(p.pageSize == 100)
    }

    @Test("Column width: nil when unset, persisted when set")
    func colWidth() {
        let (p, _) = makeIsolatedPrefs()
        #expect(p.columnWidth(database: "db", table: "t", column: "c") == nil)
        p.setColumnWidth(123.5, database: "db", table: "t", column: "c")
        #expect(p.columnWidth(database: "db", table: "t", column: "c") == 123.5)
    }

    @Test("Different (db,table,col) keys don't collide")
    func keysDistinct() {
        let (p, _) = makeIsolatedPrefs()
        p.setColumnWidth(100, database: "a", table: "x", column: "id")
        p.setColumnWidth(200, database: "b", table: "x", column: "id")
        #expect(p.columnWidth(database: "a", table: "x", column: "id") == 100)
        #expect(p.columnWidth(database: "b", table: "x", column: "id") == 200)
    }
}
