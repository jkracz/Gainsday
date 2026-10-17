import Foundation
import SyncCore

/// Keeps the user's settings in iCloud key-value storage, so they come back on reinstall.
actor CloudSettingsStore: SettingsStore {
    private static let key = "settings"
    private let store: NSUbiquitousKeyValueStore

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        store.synchronize()
    }

    func load() async -> Settings {
        guard let data = store.data(forKey: Self.key) else { return Settings() }
        return (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
    }

    func save(_ settings: Settings) async {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        store.set(data, forKey: Self.key)
        store.synchronize()
    }
}
