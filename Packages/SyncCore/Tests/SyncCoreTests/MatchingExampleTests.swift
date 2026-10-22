import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Matching example")
struct MatchingExampleTests {
    @Test("The example shows a planned event exactly as a sync pass would update it")
    func exampleMatchesSyncPass() async throws {
        let workout = SyncHarness.run(from: (7, 12), to: (7, 40))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let planned = SyncHarness.planned("Morning run", from: (7, 0), to: (7, 45), notes: "Easy pace")
        await harness.calendar.put(planned)

        _ = try await harness.engine.run(.changes(since: nil))

        let synced = try #require(await harness.calendar.allEvents.first)
        let example = MatchingExample.updating(
            planned.content,
            with: workout,
            settings: SyncHarness.defaultSettings,
            clock: FixedClock(now: SyncHarness.now)
        )
        #expect(example == synced.content)
    }

    @Test("The example keeps the user's title and notes, moves the event and adds the workout")
    func exampleContent() throws {
        let workout = SyncHarness.run(from: (7, 12), to: (7, 40))
        let planned = EventContent(
            title: "Morning run",
            start: SyncHarness.today((7, 0)),
            end: SyncHarness.today((7, 45)),
            notes: "Easy pace"
        )

        let example = MatchingExample.updating(planned, with: workout, settings: Settings(), clock: FixedClock(now: SyncHarness.now))

        #expect(example.title == "Morning run")
        #expect(example.start == workout.start)
        #expect(example.end == workout.end)
        let notes = try #require(example.notes)
        #expect(notes.hasPrefix("Easy pace\n\n— Workout logged by Gainsday —\n"))
        #expect(notes.contains("Duration: 28 min"))
        #expect(notes.contains("Planned: 7:00\u{2009}–\u{2009}7:45\u{202F}AM"))
    }

    @Test("With renaming on, the example takes the title template's title")
    func exampleRenames() {
        let workout = SyncHarness.run(from: (7, 12), to: (7, 40))
        let planned = EventContent(title: "Morning run", start: SyncHarness.today((7, 0)), end: SyncHarness.today((7, 45)))
        var settings = Settings()
        settings.renameMatchedEvents = true

        let example = MatchingExample.updating(planned, with: workout, settings: settings, clock: FixedClock(now: SyncHarness.now))

        #expect(example.title == "🏃 Running · 3.11 mi")
    }
}
