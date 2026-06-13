import Foundation

/// 持久化协议（PRD §5.1.5）。所有写操作必须原子（temp → rename），所有读必须能在
/// 主文件损坏时回退到 `.bak`，且都失败时抛 `SessionStoreError.corrupt`。
public protocol SessionStore {
    func loadAll() throws -> [SessionConfig]
    func save(_ sessions: [SessionConfig]) throws
}

public enum SessionStoreError: Error, Equatable {
    case corrupt(detail: String)
    case versionTooNew(found: Int, supported: Int)
    case ioFailed(detail: String)
}

/// JSON 容器；版本字段允许将来增字段不破坏旧客户端。
public struct SessionStoreData: Codable, Equatable, Sendable {
    public let version: Int
    public let sessions: [SessionConfig]
    public init(version: Int, sessions: [SessionConfig]) {
        self.version = version
        self.sessions = sessions
    }
}

// MARK: - 内存实现（测试用）

public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private var sessions: [SessionConfig] = []
    private let lock = NSLock()

    public init(initial: [SessionConfig] = []) {
        self.sessions = initial
    }

    public func loadAll() throws -> [SessionConfig] {
        lock.lock(); defer { lock.unlock() }
        return sessions
    }

    public func save(_ sessions: [SessionConfig]) throws {
        lock.lock(); defer { lock.unlock() }
        self.sessions = sessions
    }
}

// MARK: - JSON 文件实现（PRD §5.1.5）

public final class JSONSessionStore: SessionStore {

    /// 当前支持的最高 schema 版本。
    public static let currentSchemaVersion = 1

    private let directory: URL
    private let fileManager: FileManager

    private var jsonURL: URL { directory.appendingPathComponent("sessions.json") }
    private var bakURL:  URL { directory.appendingPathComponent("sessions.json.bak") }
    private var tmpURL:  URL { directory.appendingPathComponent("sessions.json.tmp") }

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    // MARK: load

    public func loadAll() throws -> [SessionConfig] {
        // 文件不存在 → 空列表
        guard fileManager.fileExists(atPath: jsonURL.path) else {
            return []
        }
        // 先试主文件
        do {
            return try decode(at: jsonURL)
        } catch SessionStoreError.versionTooNew(let f, let s) {
            // 版本太新：不回退 .bak（保留原文件）
            throw SessionStoreError.versionTooNew(found: f, supported: s)
        } catch {
            // 主文件解析失败 → 回退 .bak
            guard fileManager.fileExists(atPath: bakURL.path) else {
                throw SessionStoreError.corrupt(
                    detail: "Main file corrupt and no .bak: \(error)"
                )
            }
            do {
                return try decode(at: bakURL)
            } catch {
                throw SessionStoreError.corrupt(
                    detail: "Both main and .bak corrupt: \(error)"
                )
            }
        }
    }

    private func decode(at url: URL) throws -> [SessionConfig] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(SessionStoreData.self, from: data)
        guard store.version <= Self.currentSchemaVersion else {
            throw SessionStoreError.versionTooNew(
                found: store.version,
                supported: Self.currentSchemaVersion
            )
        }
        return store.sessions
    }

    // MARK: save (atomic + .bak + 0600)

    public func save(_ sessions: [SessionConfig]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = SessionStoreData(
            version: Self.currentSchemaVersion,
            sessions: sessions
        )
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            throw SessionStoreError.ioFailed(detail: "encode failed: \(error)")
        }

        // 1. 写 tmp（atomic）
        if fileManager.fileExists(atPath: tmpURL.path) {
            try? fileManager.removeItem(at: tmpURL)
        }
        do {
            try data.write(to: tmpURL, options: [.atomic])
        } catch {
            throw SessionStoreError.ioFailed(detail: "tmp write failed: \(error)")
        }

        // 2. 设置 0600
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tmpURL.path
            )
        } catch {
            try? fileManager.removeItem(at: tmpURL)
            throw SessionStoreError.ioFailed(detail: "chmod failed: \(error)")
        }

        // 3. rename tmp → main（原子替换）
        do {
            _ = try fileManager.replaceItemAt(jsonURL, withItemAt: tmpURL)
        } catch {
            try? fileManager.removeItem(at: tmpURL)
            throw SessionStoreError.ioFailed(detail: "rename failed: \(error)")
        }

        // 4. 写 .bak —— 与 main 同步保留一份，防文件级损坏（PRD §R9）。
        //    总是与 main 同步而不是"上次版本"，因为原子写已经防了写入中断；
        //    .bak 仅用于防文件系统损坏。
        try? fileManager.removeItem(at: bakURL)
        do {
            try fileManager.copyItem(at: jsonURL, to: bakURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: bakURL.path
            )
        } catch {
            // .bak 失败不致命：main 已写入；MVP 暂吞掉
        }

        // 5. 兜底：tmp 应该已不在
        if fileManager.fileExists(atPath: tmpURL.path) {
            try? fileManager.removeItem(at: tmpURL)
        }
    }
}
