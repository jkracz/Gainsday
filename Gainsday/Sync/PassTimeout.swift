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
///
/// Cancelling the caller, as SwiftUI does when a background task runs out of time,
/// cancels the operation and throws `CancellationError` at once. The engine stops
/// between workouts, and `SyncRunner` holds later passes until it has.
@discardableResult
func withTimeout<T>(_ timeout: Duration, _ operation: @escaping () async throws -> T) async throws -> T {
    let work = Task { try await operation() }
    let result = FirstResult<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            result.start(continuation)
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
    } onCancel: {
        work.cancel()
        Task { @MainActor in result.resume(with: .failure(CancellationError())) }
    }
}

/// Resumes a continuation with whichever result arrives first, including one that
/// arrives before the continuation does.
private final class FirstResult<T> {
    private var continuation: CheckedContinuation<T, any Error>?
    private var early: Result<T, any Error>?
    private var isFinished = false

    func start(_ continuation: CheckedContinuation<T, any Error>) {
        if let early {
            continuation.resume(with: early)
        } else {
            self.continuation = continuation
        }
    }

    func resume(with result: Result<T, any Error>) {
        guard !isFinished else { return }
        isFinished = true
        if let continuation {
            continuation.resume(with: result)
            self.continuation = nil
        } else {
            early = result
        }
    }
}
