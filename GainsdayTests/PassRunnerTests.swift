import Foundation
import Testing
@testable import Gainsday

/// A pass awaits Health, Calendar and iCloud. When one of them never answers, the
/// pass has to end with an error rather than show "Syncing…" for good.
@MainActor @Suite("Pass runner", .timeLimit(.minutes(1)))
struct PassRunnerTests {
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
        let runner = PassRunner()
        let stuck = StuckPass()
        defer { stuck.release() }

        await #expect(throws: PassRunner.Failure.timedOut) {
            try await runner.run(timeout: .milliseconds(200)) { await stuck.run() }
        }
    }

    @Test("While a timed-out pass is still running, no other pass starts, so they can't both add an event")
    func noOverlapWithStuckPass() async throws {
        let runner = PassRunner()
        let stuck = StuckPass()
        _ = try? await runner.run(timeout: .milliseconds(200)) { await stuck.run() }

        var secondPassRan = false
        await #expect(throws: PassRunner.Failure.stillRunning) {
            try await runner.run(timeout: .seconds(5)) { secondPassRan = true }
        }
        #expect(!secondPassRan)

        stuck.release()
        while runner.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        #expect(stuck.finished)
        try await runner.run(timeout: .seconds(5)) { secondPassRan = true }
        #expect(secondPassRan)
    }
}
