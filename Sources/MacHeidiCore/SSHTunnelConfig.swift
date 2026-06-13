import Foundation

/// SSH 隧道配置（PRD §11 v0.2）。
///
/// MVP 实现：用系统 `ssh` 命令开本地端口转发：
///   ssh -L <localPort>:<dbHost>:<dbPort> -N <sshUser>@<sshHost>
///
/// 不在这切片做：私钥认证、known_hosts 管理、SwiftNIO-SSH 原生集成。
/// 当前实现假设用户已经在系统 ~/.ssh/ 配好私钥或能用密码登录。
public struct SSHTunnelConfig: Codable, Equatable, Sendable {
    public var sshHost: String
    public var sshPort: Int
    public var sshUser: String
    /// 私钥路径，例如 "~/.ssh/id_ed25519"。空 = 用 ssh-agent / 默认查找。
    public var privateKeyPath: String

    public init(sshHost: String, sshPort: Int = 22,
                sshUser: String, privateKeyPath: String = "") {
        self.sshHost = sshHost; self.sshPort = sshPort
        self.sshUser = sshUser; self.privateKeyPath = privateKeyPath
    }

    public var isEnabled: Bool { !sshHost.isEmpty && !sshUser.isEmpty }
}
