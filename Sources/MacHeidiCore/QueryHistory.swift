import Foundation

/// 查询历史持久化（PRD §11 v0.2）。
///
/// 每条 SQL 执行后写一条；按时间倒序保留最近 N 条（默认 500）。
/// 写到 `~/Library/Application Support/MacHeidi/history.json`，原子写。
public final class QueryHistory: @unchecked Sendable {

    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let sql: String
        public let database: String?
        public let elapsedMs: Int
        public let timestamp: Date
        public let success: Bool

        public init(id: UUID = UUID(),
                    sql: String,
                    database: String?,
                    elapsedMs: Int,
                    timestamp: Date = Date(),
                    success: Bool) {
            self.id = id; self.sql = sql; self.database = database
            self.elapsedMs = elapsedMs; self.timestamp = timestamp; self.success = success
        }
    }

    public static let maxEntries = 500

    public static let shared = QueryHistory(directoryProvider: defaultDirectory)

    private let directoryProvider: () -> URL
    private let lock = NSLock()
    private var cache: [Entry]?

    public init(directoryProvider: @escaping () -> URL) {
        self.directoryProvider = directoryProvider
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("MacHeidi", isDirectory: true)
    }

    private var fileURL: URL {
        directoryProvider().appendingPathComponent("history.json")
    }

    /// 读全部条目（最新优先）。
    public func all() -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        if let c = cache { return c }
        let result = (try? loadFromDisk()) ?? []
        cache = result
        return result
    }

    /// 添加一条；自动 trim 到 maxEntries；原子落盘。
    public func append(_ entry: Entry) {
        lock.lock(); defer { lock.unlock() }
        var current = cache ?? (try? loadFromDisk()) ?? []
        current.insert(entry, at: 0)
        if current.count > Self.maxEntries {
            current = Array(current.prefix(Self.maxEntries))
        }
        cache = current
        try? saveToDisk(current)
    }

    /// 清空全部历史。
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        cache = []
        try? saveToDisk([])
    }

    // MARK: IO

    private func loadFromDisk() throws -> [Entry] {
        let dir = directoryProvider()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode([Entry].self, from: data)
    }

    private func saveToDisk(_ entries: [Entry]) throws {
        let dir = directoryProvider()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(entries)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path
        )
    }
}
