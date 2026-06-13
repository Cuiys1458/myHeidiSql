import Testing
import Foundation
@testable import MacHeidiCore

/// Covers Feature: S1.1, S1.6, S1.7 — Session CRUD, Keychain isolation, persistence
@Suite("S1 Session Persistence")
struct SessionPersistenceTests {

    // MARK: - S1.1 CRUD

    @Test("新建会话保存后能被重新读出")
    func addSessionPersists() throws {
        let store = InMemorySessionStore()
        let manager = SessionManager(store: store, keychain: MockKeychainStore())
        try manager.add(.fixture(name: "Local MySQL"))
        let all = try manager.loadAll()
        #expect(all.count == 1)
        #expect(all[0].name == "Local MySQL")
    }

    @Test("编辑会话的 hostname 后字段更新")
    func editHostnameUpdates() throws {
        let store = InMemorySessionStore()
        let manager = SessionManager(store: store, keychain: MockKeychainStore())
        try manager.add(.fixture(name: "S"))
        var s = (try manager.loadAll())[0]
        s.hostname = "10.0.0.1"
        try manager.update(s)
        #expect((try manager.loadAll())[0].hostname == "10.0.0.1")
    }

    @Test("删除会话后列表减少")
    func deleteRemoves() throws {
        let store = InMemorySessionStore()
        let manager = SessionManager(store: store, keychain: MockKeychainStore())
        try manager.add(.fixture(name: "A"))
        try manager.add(.fixture(name: "B"))
        let all = try manager.loadAll()
        try manager.delete(all[0].id)
        #expect(try manager.loadAll().count == 1)
    }

    @Test("复制会话：新 id、不同后缀、同 hostname")
    func duplicateCreatesFreshId() throws {
        let store = InMemorySessionStore()
        let manager = SessionManager(store: store, keychain: MockKeychainStore())
        try manager.add(.fixture(name: "Local"))
        let original = (try manager.loadAll())[0]
        let dup = try manager.duplicate(original.id)
        #expect(try manager.loadAll().count == 2)
        #expect(dup.name == "Local (copy)")
        #expect(dup.id != original.id)
        #expect(dup.hostname == original.hostname)
    }

    @Test("重名自动追加 (2)、(3)")
    func duplicateNameAutoSuffix() throws {
        let store = InMemorySessionStore()
        let manager = SessionManager(store: store, keychain: MockKeychainStore())
        try manager.add(.fixture(name: "Local"))
        try manager.add(.fixture(name: "Local"))
        let names = try manager.loadAll().map(\.name).sorted()
        #expect(names == ["Local", "Local (2)"])

        try manager.add(.fixture(name: "Local"))
        let ns = try manager.loadAll().map(\.name).sorted()
        #expect(ns == ["Local", "Local (2)", "Local (3)"])
    }

    @Test("空 name 校验失败")
    func emptyNameFails() throws {
        let manager = SessionManager(store: InMemorySessionStore(), keychain: MockKeychainStore())
        #expect(throws: SessionError.self) {
            try manager.add(.fixture(name: ""))
        }
    }

    @Test("name 超 64 字符校验失败")
    func longNameFails() throws {
        let manager = SessionManager(store: InMemorySessionStore(), keychain: MockKeychainStore())
        #expect(throws: SessionError.self) {
            try manager.add(.fixture(name: String(repeating: "x", count: 65)))
        }
    }

    @Test("port 范围 1..65535 校验")
    func portRangeValidated() throws {
        let manager = SessionManager(store: InMemorySessionStore(), keychain: MockKeychainStore())
        #expect(throws: SessionError.self) {
            try manager.add(.fixture(name: "x", port: 70000))
        }
        // 有效范围应该通过
        try manager.add(.fixture(name: "a", port: 1))
        try manager.add(.fixture(name: "b", port: 65535))
        try manager.add(.fixture(name: "c", port: 3306))
        #expect(try manager.loadAll().count == 3)
    }

    // MARK: - S1.6 Keychain 隔离

    @Test("保存会话后 JSON 不含密码字段")
    func jsonDoesNotContainPassword() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macheidi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = JSONSessionStore(directory: dir)
        let keychain = MockKeychainStore()
        let manager = SessionManager(store: store, keychain: keychain)
        try manager.add(.fixture(name: "Prod", password: "s3cret!"))

        let jsonURL = dir.appendingPathComponent("sessions.json")
        let raw = try Data(contentsOf: jsonURL)
        let text = String(decoding: raw, as: UTF8.self)
        #expect(!text.contains("s3cret!"))
        #expect(!text.contains("\"password\""))
    }

    @Test("添加带密码会话后 Keychain 收到该密码")
    func passwordGoesToKeychain() throws {
        let keychain = MockKeychainStore()
        let manager = SessionManager(store: InMemorySessionStore(), keychain: keychain)
        try manager.add(.fixture(name: "Prod", password: "s3cret!"))
        let session = (try manager.loadAll())[0]
        #expect(try keychain.read(account: session.id.uuidString) == "s3cret!")
    }

    @Test("删除会话后 Keychain 条目也删除")
    func deleteClearsKeychain() throws {
        let keychain = MockKeychainStore()
        let manager = SessionManager(store: InMemorySessionStore(), keychain: keychain)
        try manager.add(.fixture(name: "X", password: "pw"))
        let s = (try manager.loadAll())[0]
        try keychain.save(account: s.id.uuidString, password: "pw")
        try manager.delete(s.id)
        #expect(try keychain.read(account: s.id.uuidString) == nil)
    }

    @Test("编辑 name 不改变 Keychain account")
    func editNameDoesNotChangeKeychainAccount() throws {
        let keychain = MockKeychainStore()
        let manager = SessionManager(store: InMemorySessionStore(), keychain: keychain)
        try manager.add(.fixture(name: "Local", password: "p"))
        var s = (try manager.loadAll())[0]
        let id = s.id
        try keychain.save(account: id.uuidString, password: "p")

        s.name = "Renamed"
        try manager.update(s)
        #expect(try keychain.read(account: id.uuidString) == "p")
    }

    // MARK: - S1.7 持久化与恢复

    @Test("重启后会话完整还原")
    func restartRestoresSessions() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macheidi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 第一次保存
        let store1 = JSONSessionStore(directory: dir)
        let mgr1 = SessionManager(store: store1, keychain: MockKeychainStore())
        try mgr1.add(.fixture(name: "A", hostname: "10.0.0.1"))
        try mgr1.add(.fixture(name: "B"))

        // 第二次创建 -> 模拟重启
        let store2 = JSONSessionStore(directory: dir)
        let all = try store2.loadAll()
        #expect(all.count == 2)
        #expect(all.first { $0.name == "A" }?.hostname == "10.0.0.1")
    }

    @Test("sessions.json 损坏时回退到 .bak")
    func corruptedJsonFallsBackToBak() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macheidi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 先保存一个好的
        let store1 = JSONSessionStore(directory: dir)
        try store1.save([.fixture(name: "Good")])
        // 损坏主文件
        let jsonURL = dir.appendingPathComponent("sessions.json")
        try "corrupted".write(to: jsonURL, atomically: true, encoding: .utf8)
        // .bak 保留原好数据
        let bakURL = dir.appendingPathComponent("sessions.json.bak")
        #expect(FileManager.default.fileExists(atPath: bakURL.path))

        let store2 = JSONSessionStore(directory: dir)
        let all = try store2.loadAll()
        #expect(all.count == 1)
        #expect(all[0].name == "Good")
    }

    @Test("sessions.json 与 .bak 都损坏时抛 corrupt")
    func bothCorruptThrows() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macheidi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let json = dir.appendingPathComponent("sessions.json")
        let bak  = dir.appendingPathComponent("sessions.json.bak")
        try "nope".write(to: json, atomically: true, encoding: .utf8)
        try "also nope".write(to: bak, atomically: true, encoding: .utf8)

        #expect(throws: SessionStoreError.self) {
            _ = try JSONSessionStore(directory: dir).loadAll()
        }
    }

    @Test("文件不存在时 loadAll 返回空数组")
    func noFileReturnsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macheidi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let all = try JSONSessionStore(directory: dir).loadAll()
        #expect(all.isEmpty)
    }

    @Test("写入是原子的（temp → rename），不留 tmp 文件")
    func writeIsAtomic() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macheidi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = JSONSessionStore(directory: dir)
        try store.save([
            .fixture(name: "A"), .fixture(name: "B"), .fixture(name: "C")
        ])
        let tmpURL = dir.appendingPathComponent("sessions.json.tmp")
        #expect(!FileManager.default.fileExists(atPath: tmpURL.path))

        let jsonURL = dir.appendingPathComponent("sessions.json")
        let data = try Data(contentsOf: jsonURL)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(SessionStoreData.self, from: data)
        #expect(decoded.sessions.count == 3)
    }

    @Test("文件权限为 0600")
    func filePermissionIs0600() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macheidi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = JSONSessionStore(directory: dir)
        try store.save([.fixture(name: "X")])

        let jsonURL = dir.appendingPathComponent("sessions.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: jsonURL.path)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test("读到不认识的 version 时抛 versionTooNew，不改文件")
    func unknownVersionThrows() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macheidi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 写一个 version=99 的文件
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(
            SessionStoreData(version: 99, sessions: [
                .fixture(name: "Legacy")
            ])
        )
        let jsonURL = dir.appendingPathComponent("sessions.json")
        try data.write(to: jsonURL)

        // 读取时应当抛 versionTooNew
        var thrown: (any Error)?
        do {
            _ = try JSONSessionStore(directory: dir).loadAll()
        } catch {
            thrown = error
        }
        guard case .versionTooNew = (thrown as? SessionStoreError) else {
            Issue.record("Expected .versionTooNew, got \(String(describing: thrown))")
            return
        }

        // 文件内容不变
        let after = try Data(contentsOf: jsonURL)
        #expect(after == data)
    }
}

// MARK: - Fixtures

extension SessionConfig {
    static func fixture(
        name: String = "Test",
        hostname: String = "127.0.0.1",
        port: Int = 3306,
        user: String = "root",
        password: String = "",
        defaultDatabases: String = "",
        useSSL: Bool = false,
        comment: String = ""
    ) -> SessionConfig {
        SessionConfig(
            id: UUID(),
            name: name,
            hostname: hostname,
            port: port,
            user: user,
            password: password,
            defaultDatabases: defaultDatabases,
            useSSL: useSSL,
            comment: comment
        )
    }
}

extension SessionStoreData {
    static func fixture(version: Int = 1, sessions: [SessionConfig]) -> SessionStoreData {
        SessionStoreData(version: version, sessions: sessions)
    }
}