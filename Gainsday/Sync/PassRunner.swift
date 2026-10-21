import Foundation

/// Runs sync passes one at a time, and stops waiting for one that takes too long.
///
/// A pass awaits Health, Calendar and iCloud, and none of them promise to answer.
/// When a system service hangs, the pass would otherwise show "Syncing…" forever.
final class PassRunner {
    enum Failure: LocalizedError, Equatable {
        case timedOut
        case stillRunning

        var errorDescription: String? {
            switch self {
            case .timedOut: String(localized: "Syncing is taking too long, because Health, Calendar or iCloud isn't responding. Try again later.")
            case .stillRunning: String(localized: "The last sync still hasn't finished. Try again later.")
            }
        }
    }

    private(set) var isRunning = false

    /// Runs `operation`, or throws `timedOut` once `timeout` has passed. The operation
    /// can't be stopped from outside, so after a timeout it keeps going on its own,
    /// and further passes throw `stillRunning` until it ends, so two never overlap.
    func run<T>(timeout: Duration, _ operation: @escaping () async throws -> T) async throws -> T {
        guard !isRunning else { throw Failure.stillRunning }
        isRunning = true
        let work = Task {
            defer { isRunning = false }
            return try await operation()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let result = FirstResult(continuation)
            let timer = Task {
                try await Task.sleep(for: timeout)
                result.resume(with: .failure(Failure.timedOut))
            }
            Task {
                let outcome = await work.result
                timer.cancel()
                result.resume(with: outcome)
            }
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
