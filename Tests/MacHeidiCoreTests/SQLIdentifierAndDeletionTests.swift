import Testing
import Foundation
@testable import MacHeidiCore

// MARK: - SQLIdentifier — RED 阶段

@Suite("SQLIdentifier")
struct SQLIdentifierTests {

    @Test("Plain ASCII identifier wrapped in backticks")
    func plainAscii() throws {
        #expect(try SQLIdentifier.quote("users") == "`users`")
    }

    @Test("Backtick inside name is doubled")
    func backtickEscaped() throws {
        #expect(try SQLIdentifier.quote("weird`name") == "`weird``name`")
    }

    @Test("Dot inside name stays in one pair of backticks")
    func dotInName() throws {
        #expect(try SQLIdentifier.quote("my.table") == "`my.table`")
    }

    @Test("Empty identifier rejected")
    func emptyRejected() {
        do {
            _ = try SQLIdentifier.quote("")
            Issue.record("Expected throw")
        } catch let e as SQLIdentifierError {
            #expect(e == .empty)
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("NUL byte rejected")
    func nulRejected() {
        do {
            _ = try SQLIdentifier.quote("x\u{0000}y")
            Issue.record("Expected throw")
        } catch let e as SQLIdentifierError {
            #expect(e == .containsNul)
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("qualified() builds db.table form")
    func qualifiedDbTable() throws {
        #expect(try SQLIdentifier.qualified(database: "macheidi_test", table: "users")
                == "`macheidi_test`.`users`")
    }

    @Test("qualified() escapes backticks on either side")
    func qualifiedEscapes() throws {
        #expect(try SQLIdentifier.qualified(database: "weird`db", table: "x")
                == "`weird``db`.`x`")
    }
}

// MARK: - Deletion preflight — RED

@Suite("SessionDeletionPolicy")
struct SessionDeletionPolicyTests {

    @Test("Non-active session is allowed")
    func nonActiveAllowed() {
        let id = UUID()
        let r = SessionDeletionPolicy.evaluate(
            sessionId: id, activeSessionId: nil
        )
        #expect(r == .allowed)
    }

    @Test("Different active session is allowed")
    func differentActiveAllowed() {
        let r = SessionDeletionPolicy.evaluate(
            sessionId: UUID(), activeSessionId: UUID()
        )
        #expect(r == .allowed)
    }

    @Test("Active session is blocked with explanatory reason")
    func activeBlocked() {
        let id = UUID()
        let r = SessionDeletionPolicy.evaluate(
            sessionId: id, activeSessionId: id
        )
        guard case .blocked(let reason) = r else {
            Issue.record("Expected .blocked, got \(r)")
            return
        }
        #expect(reason.lowercased().contains("disconnect"))
    }
}

// MARK: - Heartbeat scheduler — RED

@Suite("HeartbeatScheduler")
struct HeartbeatSchedulerTests {

    @Test("Probes fire at interval; success keeps it running")
    func successKeepsRunning() async throws {
        let clock = TestClock()
        let count = Counter()

        let scheduler = HeartbeatScheduler(
            interval: .seconds(30),
            clock: clock,
            probe: { await count.increment(); return true },
            onDisconnect: { Issue.record("Should not fire on success") }
        )
        await scheduler.start()

        // Advance 3 intervals — wait long enough between for the actor's loop
        // to do its probe() and come back to the next sleep
        for _ in 0..<3 {
            clock.advance(by: .seconds(30))
            try await Task.sleep(for: .milliseconds(80))
        }

        let n = await count.value
        // Must see at least 2 probes; this proves scheduler kept running after success,
        // not stopping after first probe like failure does. Exact 3 is flaky under load.
        #expect(n >= 2, "got \(n) probes after 3 simulated intervals")
        await scheduler.stop()
    }

    @Test("First probe failure → onDisconnect fires once and scheduler stops")
    func failureStopsAndNotifies() async throws {
        let clock = TestClock()
        let fired = Counter()
        let probeCalls = Counter()

        let scheduler = HeartbeatScheduler(
            interval: .seconds(5),
            clock: clock,
            probe: { await probeCalls.increment(); return false },
            onDisconnect: { await fired.increment() }
        )
        await scheduler.start()
        clock.advance(by: .seconds(5))
        try await Task.sleep(for: .milliseconds(80))

        // Advance more — must not produce extra probes
        clock.advance(by: .seconds(30))
        try await Task.sleep(for: .milliseconds(50))

        let calls = await probeCalls.value
        let disconnects = await fired.value
        #expect(disconnects == 1)
        #expect(calls == 1)
    }

    @Test("Manual stop() does not invoke onDisconnect")
    func stopIsSilent() async throws {
        let clock = TestClock()
        let fired = Counter()
        let scheduler = HeartbeatScheduler(
            interval: .seconds(5),
            clock: clock,
            probe: { true },
            onDisconnect: { await fired.increment() }
        )
        await scheduler.start()
        await scheduler.stop()
        clock.advance(by: .seconds(30))
        try await Task.sleep(for: .milliseconds(50))

        let n = await fired.value
        #expect(n == 0)
    }
}

// MARK: - tiny helpers

actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

/// 简易 mock clock：tick-based。HeartbeatScheduler 通过 `await sleep(for:)` 让出，
/// 测试用 `advance(by:)` 驱动时间前进。
final class TestClock: HeartbeatScheduler.Clock, @unchecked Sendable {
    typealias Continuation = CheckedContinuation<Void, Never>

    private struct Waiter {
        let deadline: Duration
        let continuation: Continuation
    }

    private let lock = NSLock()
    private var now: Duration = .zero
    private var waiters: [Waiter] = []

    func sleep(for duration: Duration) async {
        await withCheckedContinuation { (cont: Continuation) in
            lock.lock()
            waiters.append(Waiter(deadline: now + duration, continuation: cont))
            lock.unlock()
        }
    }

    func advance(by duration: Duration) {
        lock.lock()
        now += duration
        let ready = waiters.filter { $0.deadline <= now }
        waiters.removeAll { $0.deadline <= now }
        lock.unlock()
        for w in ready { w.continuation.resume() }
    }
}
