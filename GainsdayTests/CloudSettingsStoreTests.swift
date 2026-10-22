import Foundation
import Synchronization
import SyncCore
import Testing
@testable import Gainsday

@Suite("Cloud settings store")
struct CloudSettingsStoreTests {
    let center = NotificationCenter()
    let cloud = FakeKeyValueStorage()

    static let restored: Settings = {
        var settings = Settings()
        settings.enabledTypes = [.running]
        settings.destinationCalendar = CalendarReference(id: "cal-1", title: "Workouts")
        settings.syncStartDate = Date(timeIntervalSince1970: 1_780_000_000)
        return settings
    }()

    /// What iCloud does after a reinstall: the restored value lands, then it says so.
    func restoreFromICloud(_ settings: Settings) {
        cloud.receive(settings)
        center.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil)
    }

    @Test("An edit made before iCloud restores settings is applied on top of the restored ones")
    func editBeforeRestoreKeepsRestoredSettings() async {
        let store = CloudSettingsStore(storage: cloud, center: center, restoreTimeout: .seconds(60))

        let edit = Task { await store.edit { $0.enabledTypes.insert(.yoga) } }
        try? await Task.sleep(for: .milliseconds(100))
        restoreFromICloud(Self.restored)
        let saved = await edit.value

        #expect(saved.destinationCalendar == Self.restored.destinationCalendar)
        #expect(saved.syncStartDate == Self.restored.syncStartDate)
        #expect(saved.enabledTypes == [.running, .yoga])
        #expect(cloud.settings == saved)
    }

    @Test("While iCloud hasn't answered, an edit shows up straight away but nothing is written")
    func editWaitsWithoutWriting() async {
        let store = CloudSettingsStore(storage: cloud, center: center, restoreTimeout: .seconds(60))

        let edit = Task { await store.edit { $0.enabledTypes = [.yoga] } }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(await store.load().enabledTypes == [.yoga])
        #expect(cloud.writeCount == 0)
        edit.cancel()
    }

    @Test("With settings already on this device, an edit saves straight away")
    func editSavesStraightAwayWhenRestored() async {
        cloud.receive(Self.restored)
        let store = CloudSettingsStore(storage: cloud, center: center, restoreTimeout: .seconds(60))

        let saved = await store.edit { $0.minimumDuration = 300 }

        #expect(saved.minimumDuration == 300)
        #expect(saved.destinationCalendar == Self.restored.destinationCalendar)
        #expect(cloud.settings == saved)
    }

    @Test("If iCloud never answers, an edit saves once the timeout passes")
    func editSavesAfterTimeout() async {
        let store = CloudSettingsStore(storage: cloud, center: center, restoreTimeout: .milliseconds(300))

        let saved = await store.edit { $0.enabledTypes = [.yoga] }

        #expect(saved.enabledTypes == [.yoga])
        #expect(cloud.settings == saved)
    }
}

/// A key-value store that only knows the keys the app sets, standing in for iCloud.
final class FakeKeyValueStorage: KeyValueStorage, Sendable {
    private let values = Mutex<[String: Data]>([:])

    /// Data that arrived from iCloud rather than from the app.
    func receive(_ settings: Settings) {
        values.withLock { $0["settings"] = try? JSONEncoder().encode(settings) }
    }

    var settings: Settings? {
        values.withLock { $0["settings"] }.flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
    }

    var writeCount: Int { writes.withLock { $0 } }
    private let writes = Mutex(0)

    func data(forKey key: String) -> Data? {
        values.withLock { $0[key] }
    }

    func setData(_ data: Data, forKey key: String) {
        values.withLock { $0[key] = data }
        writes.withLock { $0 += 1 }
    }

    func synchronize() -> Bool { true }
}
