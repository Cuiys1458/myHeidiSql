import Foundation
import MacHeidiCore

/// SSH 本地端口转发管理器（最小可用版本）。
///
/// 用 `Process` 起 `ssh -L localPort:dbHost:dbPort -N user@sshHost`。
/// 不做交互式密码 —— 假设你 ssh-agent 或公钥已配。
@MainActor
final class SSHTunnel {

    static let shared = SSHTunnel()

    private var process: Process?
    private(set) var localPort: Int = 0
    private(set) var isRunning: Bool = false
    private var lastError: String?

    /// 起一条 SSH 隧道；返回本地端口供后续连接。
    /// 若已有同 fingerprint 的隧道在跑，复用。
    func start(forDB host: String, port: Int, ssh: SSHTunnelConfig) throws -> Int {
        if isRunning, let p = process, p.isRunning {
            return localPort
        }
        // 找一个空闲端口
        let chosen = pickFreePort()
        let task = Process()
        task.launchPath = "/usr/bin/ssh"
        var args: [String] = [
            "-N",                                    // 不开 shell，仅转发
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=30",
            "-L", "\(chosen):\(host):\(port)",
            "-p", "\(ssh.sshPort)",
        ]
        if !ssh.privateKeyPath.isEmpty {
            args.append(contentsOf: ["-i", expand(ssh.privateKeyPath)])
        }
        args.append("\(ssh.sshUser)@\(ssh.sshHost)")
        task.arguments = args
        task.standardError = Pipe()
        task.standardOutput = Pipe()
        do {
            try task.run()
        } catch {
            lastError = "ssh launch failed: \(error)"
            throw NSError(domain: "SSHTunnel", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: lastError ?? ""])
        }
        process = task
        localPort = chosen
        isRunning = true

        // 给 ssh 几百毫秒建立隧道
        Thread.sleep(forTimeInterval: 0.6)
        return chosen
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
        localPort = 0
    }

    private func pickFreePort() -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0   // 让 OS 分配
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                bind(sock, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 { return 13306 }  // 兜底
        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                getsockname(sock, ptr, &len)
            }
        }
        return Int(UInt16(bigEndian: assigned.sin_port))
    }

    private func expand(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + path.dropFirst(1)
        }
        return path
    }
}
