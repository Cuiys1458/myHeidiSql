import Foundation

/// 一个 MySQL 连接配置 + 用户起的名字。未连接时也存在（PRD §5.1.2）。
///
/// **不**包含密码字段 —— 密码只能通过 `KeychainStore` 读写，UUID 作为 account。
/// 这样可以静态保证：任何编码到 JSON 的 `SessionConfig` 都不会泄露密码。
public struct SessionConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var hostname: String
    public var port: Int
    public var user: String
    public var defaultDatabases: String
    public var useSSL: Bool
    public var comment: String

    /// SSH 隧道配置（PRD §11 v0.2）。空 → 直连。
    public var sshConfig: SSHTunnelConfig?

    public var createdAt: Date
    public var lastUsedAt: Date?

    /// 仅在内存中携带，**不**进 Codable —— 见 CodingKeys。
    public var password: String

    public init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int,
        user: String,
        password: String = "",
        defaultDatabases: String = "",
        useSSL: Bool = false,
        comment: String = "",
        sshConfig: SSHTunnelConfig? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.user = user
        self.password = password
        self.defaultDatabases = defaultDatabases
        self.useSSL = useSSL
        self.comment = comment
        self.sshConfig = sshConfig
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// 故意省略 `password` —— 这是 PRD §10 的安全要求由类型系统保证。
    private enum CodingKeys: String, CodingKey {
        case id, name, hostname, port, user
        case defaultDatabases, useSSL, comment
        case sshConfig
        case createdAt, lastUsedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.hostname = try c.decode(String.self, forKey: .hostname)
        self.port = try c.decode(Int.self, forKey: .port)
        self.user = try c.decode(String.self, forKey: .user)
        self.defaultDatabases = try c.decodeIfPresent(String.self, forKey: .defaultDatabases) ?? ""
        self.useSSL = try c.decodeIfPresent(Bool.self, forKey: .useSSL) ?? false
        self.comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""
        self.sshConfig = try c.decodeIfPresent(SSHTunnelConfig.self, forKey: .sshConfig)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        self.password = ""    // 不从 JSON 还原密码；上层从 Keychain 读
    }
}

// MARK: - 校验（PRD §5.1.2 字段表）

public enum SessionError: Error, Equatable {
    case invalidName(reason: String)
    case invalidPort(value: Int)
    case invalidUser(reason: String)
    case invalidPassword(reason: String)
    case notFound(id: UUID)
}

extension SessionConfig {
    /// 在持久化之前调用。校验失败抛 `SessionError`。
    func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            throw SessionError.invalidName(reason: "Name cannot be empty")
        }
        guard trimmedName.count <= 64 else {
            throw SessionError.invalidName(reason: "Name exceeds 64 characters")
        }
        guard (1...65535).contains(port) else {
            throw SessionError.invalidPort(value: port)
        }
        guard !user.isEmpty, user.count <= 32 else {
            throw SessionError.invalidUser(reason: "User must be 1..32 characters")
        }
        guard password.count <= 256 else {
            throw SessionError.invalidPassword(reason: "Password exceeds 256 characters")
        }
    }
}
