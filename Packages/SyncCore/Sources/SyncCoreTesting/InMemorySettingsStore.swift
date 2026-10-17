import Foundation
import SyncCore

/// Settings held in memory.
public actor InMemorySettingsStore: SettingsStore {
    private var settings: Settings

    public init(_ settings: Settings = Settings()) {
        self.settings = settings
    }

    public func load() async -> Settings {
        settings
    }

    public func save(_ settings: Settings) async {
        self.settings = settings
    }
}
