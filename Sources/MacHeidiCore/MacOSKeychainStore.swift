import Foundation
import Security

/// macOS Keychain 实现 (PRD §5.5.5)
///
/// 使用 Generic Password Item，`service = com.macheidi.session`。
/// account 是 `SessionConfig.id.uuidString`。
public final class MacOSKeychainStore: KeychainStore {

    public static let defaultService = "com.macheidi.session"

    private let service: String

    public init(service: String = MacOSKeychainStore.defaultService) {
        self.service = service
    }

    public func save(account: String, password: String) throws {
        // upsert：先删后加，避免 duplicate item 错
        try? delete(account: account)

        guard let data = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecValueData as String:    data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return
        case errSecUserCanceled: throw KeychainError.denied
        default: throw KeychainError.unhandled(code: status)
        }
    }

    public func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let s = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return s
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled:
            throw KeychainError.denied
        default:
            throw KeychainError.unhandled(code: status)
        }
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound: return
        case errSecUserCanceled: throw KeychainError.denied
        default: throw KeychainError.unhandled(code: status)
        }
    }
}
