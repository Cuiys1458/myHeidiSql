import Foundation

/// 协调 `SessionStore`（明文字段持久化）与 `KeychainStore`（密码）的门面。
///
/// 上层 UI / ViewModel **不**直接操作 store/keychain；这里集中
/// 校验、重名去重、Keychain 同步的不变式（PRD §5.1）。
public final class SessionManager {

    private let store: SessionStore
    private let keychain: KeychainStore

    public init(store: SessionStore, keychain: KeychainStore) {
        self.store = store
        self.keychain = keychain
    }

    // MARK: - 读

    /// 读所有 session（**不读 Keychain**）。列表展示用。
    /// 这样 macOS 不会因为"读 N 次密码"对每条都弹授权对话框。
    public func loadAll() throws -> [SessionConfig] {
        try store.loadAll()
    }

    /// 读所有 session 并把密码从 Keychain 补回 —— 仅在确实需要密码时调用
    /// （比如导出 / 复制会话时）。会触发 macOS Keychain 授权弹窗。
    public func loadAllWithPasswords() throws -> [SessionConfig] {
        var sessions = try store.loadAll()
        for i in sessions.indices {
            if let pw = try? keychain.read(account: sessions[i].id.uuidString) {
                sessions[i].password = pw
            }
        }
        return sessions
    }

    /// 读单个 session 并补密码。点击 Open 时调用。
    public func loadOneWithPassword(id: UUID) throws -> SessionConfig? {
        let all = try store.loadAll()
        guard var s = all.first(where: { $0.id == id }) else { return nil }
        if let pw = try? keychain.read(account: id.uuidString) {
            s.password = pw
        }
        return s
    }

    // MARK: - 写

    /// 添加。若 name 已存在则自动追加 "(2)"、"(3)" …
    public func add(_ session: SessionConfig) throws {
        var s = session
        s.name = try resolveName(s.name, excluding: nil)
        try s.validate()

        var all = try store.loadAll()
        all.append(s)
        try persist(all, andSyncPasswordFor: s)
    }

    public func update(_ session: SessionConfig) throws {
        var s = session
        s.name = try resolveName(s.name, excluding: s.id)
        try s.validate()

        var all = try store.loadAll()
        guard let idx = all.firstIndex(where: { $0.id == s.id }) else {
            throw SessionError.notFound(id: s.id)
        }
        all[idx] = s
        try persist(all, andSyncPasswordFor: s)
    }

    public func delete(_ id: UUID) throws {
        var all = try store.loadAll()
        all.removeAll { $0.id == id }
        try store.save(all)
        try keychain.delete(account: id.uuidString)
    }

    /// 复制：克隆所有字段（含密码）；name 加 "(copy)"，必要时再 "(copy 2)" 等。
    @discardableResult
    public func duplicate(_ id: UUID) throws -> SessionConfig {
        let all = try loadAllWithPasswords()    // 复制需要带密码
        guard let original = all.first(where: { $0.id == id }) else {
            throw SessionError.notFound(id: id)
        }
        let baseName = "\(original.name) (copy)"
        var dup = original
        dup.id = UUID()
        dup.name = try resolveName(baseName, excluding: nil)
        dup.createdAt = Date()
        dup.lastUsedAt = nil
        try dup.validate()

        var next = try store.loadAll()
        next.append(dup)
        try persist(next, andSyncPasswordFor: dup)
        return dup
    }

    // MARK: - 私有

    private func persist(_ all: [SessionConfig],
                         andSyncPasswordFor session: SessionConfig) throws {
        // 1. 写 store（不含密码）
        try store.save(all)
        // 2. 同步 Keychain
        if session.password.isEmpty {
            try keychain.delete(account: session.id.uuidString)
        } else {
            try keychain.save(account: session.id.uuidString, password: session.password)
        }
    }

    /// 如果 `name` 与现有（除 `excluding` 外）的会话冲突，自动追加 (2)/(3)…
    private func resolveName(_ raw: String, excluding excludedId: UUID?) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw SessionError.invalidName(reason: "Name cannot be empty")
        }
        let existing = try store.loadAll()
            .filter { $0.id != excludedId }
            .map { $0.name }
        let used = Set(existing)
        if !used.contains(trimmed) { return trimmed }
        // 已存在 → 找下一个 "name (n)"，n 从 2 起
        var n = 2
        while used.contains("\(trimmed) (\(n))") {
            n += 1
        }
        return "\(trimmed) (\(n))"
    }
}
