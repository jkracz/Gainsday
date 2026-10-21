import Foundation

/// Thrown when a pass takes longer than its timeout.
///
/// A pass awaits Health, Calendar and iCloud, and none of them promise to answer.
/// When a system service hangs, the pass would otherwise show "Syncing…" forever,
/// and every pass queued behind it would wait too.
struct PassTimedOut: LocalizedError, Equatable {
    var errorDescription: String? {
        String(localized: "Syncing is taking too long, because Health, Calendar or iCloud isn't responding. Try again later.")
    }
}

/// Runs `operation`, or throws `PassTimedOut` once `timeout` has passed. The operation
/// can't be stopped from outside, so after a timeout it keeps going on its own.
/// `SyncRunner` still runs passes one at a time, so a later pass waits for it.
func withTimeout<T>(_ timeout: Duration, _ operation: @escaping () async throws -> T) async throws -> T {
    let work = Task { try await operation() }
    return try await withCheckedThrowingContinuation { continuation in
        let result = FirstResult(continuation)
        let timer = Task {
            try await Task.sleep(for: timeout)
            result.resume(with: .failure(PassTimedOut()))
        }
        Task {
            let outcome = await work.result
            timer.cancel()
            result.resume(with: outcome)
        }
    }
}

/// Resumes a continuation with whichever result arrives first.
private final class FirstResult<T> {
    private var continuation: CheckedContinuation<T, any Error>?

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
