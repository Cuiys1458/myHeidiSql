import Testing
import Foundation
@testable import MacHeidiCore

@Suite("QueryHistory")
struct QueryHistoryTests {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Empty history returns empty array")
    func empty() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = QueryHistory(directoryProvider: { dir })
        #expect(h.all().isEmpty)
    }

    @Test("Append + persist + reload")
    func appendPersists() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = QueryHistory(directoryProvider: { dir })
        h.append(.init(sql: "SELECT 1", database: "db", elapsedMs: 5, success: true))
        h.append(.init(sql: "UPDATE t SET x=1", database: "db", elapsedMs: 22, success: true))

        // new instance reads from disk
        let h2 = QueryHistory(directoryProvider: { dir })
        let all = h2.all()
        #expect(all.count == 2)
        // 倒序：最新在前
        #expect(all[0].sql == "UPDATE t SET x=1")
        #expect(all[1].sql == "SELECT 1")
    }

    @Test("Clear empties history")
    func clear() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = QueryHistory(directoryProvider: { dir })
        h.append(.init(sql: "SELECT 1", database: nil, elapsedMs: 1, success: true))
        h.clear()
        #expect(h.all().isEmpty)
    }
}
