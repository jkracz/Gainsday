import Foundation

/// Loads and saves the user's settings (iCloud key-value storage in the app).
public protocol SettingsStore: Sendable {
    func load() async -> Settings

    func save(_ settings: Settings) async
}
