import Foundation

/// Keychain 抽象（PRD §5.5.5）。
///
/// 真实实现（基于 `SecItemAdd` 等）在后续 macOS-only 模块加；
/// 单元测试用 `MockKeychainStore`。
public protocol KeychainStore: AnyObject {
    func save(account: String, password: String) throws
    func read(account: String) throws -> String?
    func delete(account: String) throws
}

public enum KeychainError: Error, Equatable {
    case denied
    case unhandled(code: Int32)
    case invalidData
}

/// 内存实现，测试与 UI 预览用。线程安全（NSLock）。
public final class MockKeychainStore: KeychainStore, @unchecked Sendable {
    private var entries: [String: String] = [:]
    private let lock = NSLock()

    /// 模拟用户拒绝：设为 `true` 后所有调用抛 `.denied`。
    public var denyAll: Bool = false

    public init() {}

    public func save(account: String, password: String) throws {
        lock.lock(); defer { lock.unlock() }
        if denyAll { throw KeychainError.denied }
        entries[account] = password
    }

    public func read(account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        if denyAll { throw KeychainError.denied }
        return entries[account]
    }

    public func delete(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        if denyAll { throw KeychainError.denied }
        entries.removeValue(forKey: account)
    }
}
