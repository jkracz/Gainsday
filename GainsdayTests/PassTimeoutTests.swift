import Foundation
import Testing
@testable import Gainsday

/// A pass awaits Health, Calendar and iCloud. When one of them never answers, the
/// pass has to end with an error rather than show "Syncing…" for good.
@MainActor @Suite("Pass timeout", .timeLimit(.minutes(1)))
struct PassTimeoutTests {
    /// A pass that only finishes once `release()` is called, like a Health query
    /// waiting on a daemon that isn't answering.
    final class StuckPass {
        private let (stream, continuation) = AsyncStream<Void>.makeStream()
        private(set) var finished = false

        func run() async {
            for await _ in stream {}
            finished = true
        }

        func release() {
            continuation.finish()
        }
    }

    @Test("A pass that never finishes ends with a timeout instead of running forever")
    func timesOut() async {
        let stuck = StuckPass()
        defer { stuck.release() }

        await #expect(throws: PassTimedOut()) {
            try await withTimeout(.milliseconds(200)) { await stuck.run() }
        }
    }

    @Test("A pass that timed out still finishes once the service answers, so its result is kept")
    func timedOutPassFinishesLater() async throws {
        let stuck = StuckPass()
        _ = try? await withTimeout(.milliseconds(200)) { await stuck.run() }
        #expect(!stuck.finished)

        stuck.release()
        while !stuck.finished { try await Task.sleep(for: .milliseconds(20)) }
        #expect(stuck.finished)
    }

    @Test("Cancelling the caller, as background expiry does, cancels the pass")
    func cancellationReachesThePass() async throws {
        let sawCancellation = Flag()
        let caller = Task {
            try await withTimeout(.seconds(30)) {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    sawCancellation.set()
                }
            }
        }
        try await Task.sleep(for: .milliseconds(100))

        caller.cancel()

        while !sawCancellation.isSet { try await Task.sleep(for: .milliseconds(20)) }
        #expect(sawCancellation.isSet)
    }

    @Test("A cancelled caller stops waiting at once, even for a pass that is slow to stop")
    func cancelledCallerStopsWaiting() async {
        let stuck = StuckPass()
        defer { stuck.release() }
        let caller = Task { try await withTimeout(.seconds(30)) { await stuck.run() } }
        try? await Task.sleep(for: .milliseconds(100))
        let clock = ContinuousClock()
        let cancelled = clock.now

        caller.cancel()
        let result = await caller.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(clock.now - cancelled < .seconds(5))
    }

    @Test("A caller that is already cancelled stops at once")
    func alreadyCancelledCaller() async {
        let stuck = StuckPass()
        defer { stuck.release() }
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withTimeout(.seconds(30)) { await stuck.run() }
        }

        let result = await caller.result

        #expect(throws: CancellationError.self) { try result.get() }
    }

    final class Flag {
        private(set) var isSet = false
        func set() { isSet = true }
    }

    @Test("A pass that finishes in time returns its result")
    func finishesInTime() async throws {
        #expect(try await withTimeout(.seconds(5)) { 42 } == 42)
    }
}
