import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Sync with templates")
struct TemplateSyncTests {
    @Test("A synced event is written with the default templates, formatted for the clock's locale, then the footer")
    func defaultTemplates() async throws {
        let workout = SyncHarness.run(minutes: 30)
        let harness = SyncHarness(workouts: [workout])

        _ = try await harness.engine.run(.changes(since: nil))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(event.content.title == "🏃 Running · 3.11 mi")
        #expect(event.content.notes == """
            Duration: 30 min
            Distance: 3.11 mi
            Pace: 9:39 /mi

            — Logged by Gainsday · \(workout.shortID)
            """)
    }

    @Test("A per-type template override is used for its type, and the global template for the rest")
    func perTypeOverride() async throws {
        let run = SyncHarness.run(minutes: 30, minutesAgo: 60)
        let ride = SyncHarness.ride()
        var settings = SyncHarness.defaultSettings
        settings.template = EventTemplate(title: "{type} at {start}", notes: "Took {duration}")
        settings.templateOverrides = [.running: EventTemplate(title: "Run · {distance}", notes: "Avg {avgHR}")]
        settings.footerEnabled = false
        let harness = SyncHarness(workouts: [run, ride], settings: settings)

        _ = try await harness.engine.run(.changes(since: nil))

        let events = await harness.calendar.allEvents
        #expect(events.map(\.content.title) == ["Run · 3.11 mi", "Cycling at 1:43\u{202F}PM"])
        #expect(events.map(\.content.notes) == ["Avg 150 bpm", "Took 20 min"])
    }
}

extension SyncHarness {
    /// A 20-minute ride with no metrics that started at 13:43 UTC.
    static func ride() -> Workout {
        let end = now.addingTimeInterval(-10 * 60)
        return Workout(activityType: .cycling, start: end.addingTimeInterval(-20 * 60), end: end, source: watch)
    }
}
