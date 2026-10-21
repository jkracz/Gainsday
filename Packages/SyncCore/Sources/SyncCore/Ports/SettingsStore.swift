import Foundation

/// Loads and saves the user's settings (iCloud key-value storage in the app).
public protocol SettingsStore: Sendable {
    func load() async -> Settings

    func save(_ settings: Settings) async

    /// Applies `change` to the latest settings and saves them in one step, so a change
    /// made elsewhere in the meantime isn't overwritten. Returns the saved settings.
    @discardableResult
    func edit(_ change: @escaping @Sendable (inout Settings) -> Void) async -> Settings
}
