import Foundation
import Synchronization
import SyncCore

/// Keeps the user's settings in iCloud key-value storage, so they come back on reinstall.
///
/// After a reinstall, iCloud restores the settings a few seconds after launch. Edits made
/// before then are held back and applied on top of the restored settings, so the defaults
/// on a fresh install never overwrite the user's real settings in iCloud.
actor CloudSettingsStore: SettingsStore {
    /// How long after launch to wait for iCloud before saving anyway. With no iCloud
    /// account or no network, nothing ever arrives.
    nonisolated static let defaultRestoreTimeout: Duration = .seconds(10)
    private static let key = "settings"
    private let storage: any KeyValueStorage
    private let center: NotificationCenter
    private let restoreDeadline: ContinuousClock.Instant
    /// Set once iCloud has restored settings, or there were some on this device already.
    private let restored = Flag()
    private var pendingEdits: [@Sendable (inout Settings) -> Void] = []
    private let observation: Task<Void, Never>

    init(
        storage: any KeyValueStorage = NSUbiquitousKeyValueStore.default,
        center: NotificationCenter = .default,
        restoreTimeout: Duration = defaultRestoreTimeout
    ) {
        self.storage = storage
        self.center = center
        restoreDeadline = .now + restoreTimeout
        storage.synchronize()
        // Settings already on this device were either restored or written by this install.
        if storage.data(forKey: Self.key) != nil {
            restored.set()
        }
        let changes = center.signals(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
        observation = Task { [restored] in
            for await _ in changes {
                restored.set()
            }
        }
    }

    deinit {
        observation.cancel()
    }

    /// The saved settings, with any edits still waiting for iCloud applied on top.
    func load() async -> Settings {
        var settings = stored()
        for edit in pendingEdits {
            edit(&settings)
        }
        return settings
    }

    /// Fires when iCloud delivers settings changed elsewhere, such as after a reinstall.
    nonisolated func externalChanges() -> AsyncStream<Void> {
        center.signals(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
    }

    /// Applies `change` to the latest settings and saves them. Waits first, until iCloud
    /// has restored settings or the timeout passes, so the change lands on the restored ones.
    @discardableResult
    func edit(_ change: @escaping @Sendable (inout Settings) -> Void) async -> Settings {
        pendingEdits.append(change)
        await waitUntilRestored()
        savePendingEdits()
        return stored()
    }

    /// Replaces the settings outright. Prefer `edit(_:)`, which can't undo a restore.
    func save(_ settings: Settings) async {
        await edit { $0 = settings }
    }

    private func waitUntilRestored() async {
        while !restored.isSet, ContinuousClock.now < restoreDeadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func savePendingEdits() {
        guard !pendingEdits.isEmpty else { return }
        var settings = stored()
        for edit in pendingEdits {
            edit(&settings)
        }
        pendingEdits.removeAll()
        guard let data = try? JSONEncoder().encode(settings) else { return }
        storage.setData(data, forKey: Self.key)
        storage.synchronize()
    }

    private func stored() -> Settings {
        guard let data = storage.data(forKey: Self.key) else { return Settings() }
        return (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
    }
}

/// A flag any thread can set once.
private nonisolated final class Flag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool { value.withLock { $0 } }

    func set() {
        value.withLock { $0 = true }
    }
}

/// The part of `NSUbiquitousKeyValueStore` the settings store uses.
nonisolated protocol KeyValueStorage: Sendable {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

// Apple documents the store as safe to use from any thread.
nonisolated extension NSUbiquitousKeyValueStore: @retroactive @unchecked Sendable, KeyValueStorage {
    func setData(_ data: Data, forKey key: String) {
        set(data, forKey: key)
    }
}
