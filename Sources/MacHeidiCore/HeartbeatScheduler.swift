import Foundation

/// 心跳调度器（PRD §13 R10）。
///
/// - interval 30 秒。一次 probe 返回 false 立刻停止并调用 onDisconnect。
/// 用户主动 stop() 不触发 onDisconnect。
public actor HeartbeatScheduler {

    public typealias Probe = @Sendable () async -> Bool
    public typealias DisconnectHandler = @Sendable () async -> Void

    private let interval: Duration
    private let clock: Clock
    private let probe: Probe
    private let onDisconnect: DisconnectHandler
    private var running = false
    private var stopped = false

    /// 注入 clock override，为测试用。
    public protocol Clock: Sendable {
        func sleep(for duration: Duration) async
    }

    /// 生产环境默认系统时钟。
    public struct SystemClock: Clock, Sendable {
        public init() {}
        public func sleep(for duration: Duration) async {
            try? await Task.sleep(for: duration, tolerance: .seconds(2))
        }
    }

    // MARK: - init

    public init(
        interval: Duration = .seconds(30),
        clock: Clock = SystemClock(),
        probe: @escaping Probe,
        onDisconnect: @escaping DisconnectHandler
    ) {
        self.interval = interval
        self.clock = clock
        self.probe = probe
        self.onDisconnect = onDisconnect
    }

    public func start() {
        guard !running else { return }
        running = true
        stopped = false
        Task { await loop() }
    }

    public func stop() {
        stopped = true
    }

    // MARK: - loop

    private func loop() async {
        while !stopped {
            await clock.sleep(for: interval)
            if stopped { break }
            let ok = await probe()
            if !ok {
                stopped = true
                await onDisconnect()
                break
            }
        }
        running = false
    }
}
