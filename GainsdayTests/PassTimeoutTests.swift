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

    @Test("A pass that finishes in time returns its result")
    func finishesInTime() async throws {
        #expect(try await withTimeout(.seconds(5)) { 42 } == 42)
    }
}
