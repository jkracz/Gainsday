import CoreData
import Foundation

/// Tracks whether the ledger's first iCloud import has finished on this install, so
/// the first pass after a reinstall doesn't race the download and duplicate events.
///
/// SwiftData syncs through `NSPersistentCloudKitContainer`, which posts an event for
/// each import. Create the monitor early in launch so it sees the first one.
final class CloudImportMonitor {
    /// How long the first pass waits before going ahead. With full access, the
    /// footer scan still stops duplicates if the import is slower than this.
    nonisolated static let defaultTimeout: Duration = .seconds(20)
    private static let importedKey = "hasImportedLedgerOnce"

    private let defaults: UserDefaults
    private let hasICloudAccount: () -> Bool
    private var observation: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        center: NotificationCenter = .default,
        hasICloudAccount: @escaping () -> Bool = { FileManager.default.ubiquityIdentityToken != nil }
    ) {
        self.defaults = defaults
        self.hasICloudAccount = hasICloudAccount
        let imports = Self.finishedImports(on: center)
        observation = Task { [weak self] in
            for await _ in imports {
                self?.markImportFinished()
            }
        }
    }

    isolated deinit {
        observation?.cancel()
    }

    /// Ready once an import has finished on this install, or straight away with no
    /// iCloud account, since then there's nothing to import.
    var isReady: Bool {
        defaults.bool(forKey: Self.importedKey) || !hasICloudAccount()
    }

    func markImportFinished() {
        defaults.set(true, forKey: Self.importedKey)
    }

    /// Waits until the monitor is ready. Returns false if `timeout` passed first.
    func waitForInitialImport(timeout: Duration = defaultTimeout) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !isReady {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return true
    }

    /// Yields once per successfully finished CloudKit import.
    private nonisolated static func finishedImports(on center: NotificationCenter) -> AsyncStream<Void> {
        AsyncStream { continuation in
            nonisolated(unsafe) let observer = center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
            ) { notification in
                let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                guard let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                      event.type == .import, event.endDate != nil, event.succeeded else { return }
                continuation.yield()
            }
            continuation.onTermination = { _ in
                center.removeObserver(observer)
            }
        }
    }
}
