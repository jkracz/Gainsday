import Foundation

extension NotificationCenter {
    /// Yields once per matching notification, without the non-`Sendable` payload, and
    /// stops observing when the listener goes away. Observing starts when this is called.
    nonisolated func signals(named name: Notification.Name, object: AnyObject? = nil) -> AsyncStream<Void> {
        AsyncStream { continuation in
            nonisolated(unsafe) let observer = addObserver(forName: name, object: object, queue: nil) { _ in
                continuation.yield()
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeObserver(observer)
            }
        }
    }
}
