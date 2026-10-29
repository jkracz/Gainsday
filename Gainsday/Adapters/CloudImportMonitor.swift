import CloudKit
import CoreData
import Foundation
import SyncCore

/// Tracks whether the ledger's first iCloud import has finished on this install, so
/// the first pass after a reinstall doesn't race the download and duplicate events.
///
/// SwiftData syncs through `NSPersistentCloudKitContainer`, which posts an event for
/// each import. Create the monitor before the ledger's container, so it sees the first
/// one. Only the first pass on an install waits: if no import is seen by then, later
/// passes with full access rely on the footer scan rather than wait again. Add-only
/// access can't read events back to spot duplicates, so it writes nothing until then.
/// Thrown by a backfill that can't write yet, see `CloudImportMonitor.isSafeToWrite(with:)`.
struct WaitingForICloudImport: LocalizedError {
    var errorDescription: String? {
        String(localized: "Waiting for your Gainsday records to download from iCloud. With add-only access, workouts are added once they have, so none are added twice.")
    }
}

final class CloudImportMonitor {
    /// How long the first pass waits before going ahead. With full access, the
    /// footer scan still stops duplicates if the import is slower than this.
    nonisolated static let defaultTimeout: Duration = .seconds(20)
    private static let importedKey = "hasImportedLedgerOnce"
    private static let waitedKey = "hasWaitedForLedgerImport"

    private let defaults: UserDefaults
    private let accountStatus: () async throws -> CKAccountStatus
    private var observation: Task<Void, Never>?
    /// Runs after each import finishes, such as to scrub the records it brought in.
    var afterEachImport: (() async -> Void)?

    init(
        defaults: UserDefaults = .standard,
        center: NotificationCenter = .default,
        accountStatus: @escaping () async throws -> CKAccountStatus = { try await CloudImportMonitor.cloudKitAccountStatus() }
    ) {
        self.defaults = defaults
        self.accountStatus = accountStatus
        let imports = Self.finishedImports(on: center)
        observation = Task { [weak self] in
            for await _ in imports {
                await self?.importFinished()
            }
        }
    }

    isolated deinit {
        observation?.cancel()
    }

    /// Ready once an import has finished on this install, or straight away when iCloud
    /// confirms there's no account, since then there's nothing to import. Any other
    /// status, or a failed check, may hide an account whose ledger is on the way.
    var isReady: Bool {
        get async {
            if hasImported { return true }
            return (try? await accountStatus()) == .noAccount
        }
    }

    private var hasImported: Bool {
        defaults.bool(forKey: Self.importedKey)
    }

    /// Whether the ledger syncs through iCloud. CloudKit, not iCloud Drive: the app has
    /// no iCloud Drive entitlement, so `ubiquityIdentityToken` says nothing about it.
    nonisolated static func cloudKitAccountStatus() async throws -> CKAccountStatus {
        try await CKContainer.default().accountStatus()
    }

    func markImportFinished() {
        defaults.set(true, forKey: Self.importedKey)
    }

    /// Records a finished import, then runs `afterEachImport`.
    func importFinished() async {
        markImportFinished()
        await afterEachImport?()
    }

    /// Waits until the monitor is ready, on the first pass after installing only.
    /// Returns false if `timeout` passed first, or an earlier wait already gave up.
    func waitForInitialImport(timeout: Duration = defaultTimeout) async -> Bool {
        guard !defaults.bool(forKey: Self.waitedKey) else { return await isReady }
        defer { defaults.set(true, forKey: Self.waitedKey) }
        guard await !isReady else { return true }
        let deadline = ContinuousClock.now + timeout
        while !hasImported {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return true
    }

    /// Whether a pass or backfill can write events now, after waiting for the first
    /// import as `waitForInitialImport` does. With full access the footer scan stops
    /// duplicates, so it always can. Add-only access can't spot them, so it waits for
    /// the import on every pass until one has finished.
    func isSafeToWrite(with access: AccessMode, timeout: Duration = defaultTimeout) async -> Bool {
        let imported = await waitForInitialImport(timeout: timeout)
        return imported || access != .addOnly
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
