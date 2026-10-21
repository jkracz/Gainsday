import Foundation
import SyncCore
import Testing

@Suite("Settings backup")
struct SettingsCodingTests {
    @Test("Every setting survives the round trip through iCloud")
    func roundTrip() throws {
        let settings = Settings(
            enabledTypes: [.running, .yoga],
            minimumDuration: 25 * 60,
            sourceAllowlist: ["com.apple.health", "com.strava.stravaride"],
            destinationCalendar: CalendarReference(id: "abc", title: "Training"),
            template: EventTemplate(title: "{type}", notes: "{duration}"),
            templateOverrides: [.yoga: EventTemplate(title: "🧘 {duration}", notes: "")],
            footerEnabled: false,
            preferredAccessMode: .addOnly,
            syncStartDate: Date(timeIntervalSince1970: 1_780_000_000),
            matchingEnabled: true,
            matchMode: .createSeparateEvent,
            searchCalendars: [CalendarReference(id: "home", title: "Home")],
            matchWindow: 30 * 60,
            matchKeywords: [.running: ["Parkrun"]],
            matchModelEnabled: false,
            holdUnclearMatchesForReview: true,
            renameMatchedEvents: true
        )

        let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

        #expect(restored == settings)
    }

    @Test("Settings saved by an older version, missing newer keys, still load, with defaults for what's missing")
    func olderBackupLoads() throws {
        let json = #"{"enabledTypes":[37],"destinationCalendar":{"id":"abc","title":"Training"},"syncStartDate":0}"#

        let restored = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))

        #expect(restored.enabledTypes == [.running])
        #expect(restored.destinationCalendar == CalendarReference(id: "abc", title: "Training"))
        #expect(restored.syncStartDate == Date(timeIntervalSinceReferenceDate: 0))
        #expect(restored.minimumDuration == 10 * 60)
        #expect(restored.template == .default)
        #expect(restored.footerEnabled)
        #expect(restored.preferredAccessMode == .full)
        #expect(restored.matchingEnabled == false)
        #expect(restored.matchMode == .updatePlannedEvent)
        #expect(restored.searchCalendars == nil)
        #expect(restored.matchWindow == 60 * 60)
        #expect(restored.matchKeywords.isEmpty)
        #expect(restored.matchModelEnabled)
        #expect(restored.holdUnclearMatchesForReview == false)
        #expect(restored.renameMatchedEvents == false)
    }

    @Test("An empty backup loads as the defaults")
    func emptyBackupLoads() throws {
        let restored = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))

        #expect(restored == Settings())
    }

    @Test("A setting this version can't read falls back to its default and the rest still load")
    func unreadableSettingFallsBack() throws {
        let json = #"{"preferredAccessMode":"someFutureMode","minimumDuration":900,"syncStartDate":0}"#

        let restored = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))

        #expect(restored.preferredAccessMode == .full)
        #expect(restored.minimumDuration == 15 * 60)
        #expect(restored.syncStartDate == Date(timeIntervalSinceReferenceDate: 0))
    }
}
