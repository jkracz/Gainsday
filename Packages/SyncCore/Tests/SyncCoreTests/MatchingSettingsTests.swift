import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Matching settings")
struct MatchingSettingsTests {
    @Test("Calendars that aren't selected are never read for matching")
    func unselectedCalendarsAreNeverRead() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout]) {
            $0.searchCalendars = [CalendarReference(id: SyncHarness.work.id, title: SyncHarness.work.title)]
        }
        await harness.calendar.addCalendar(SyncHarness.family)
        let unselected = [SyncHarness.personal, SyncHarness.family, SyncHarness.destination].map {
            SyncHarness.planned("\($0.title) run", from: (10, 0), to: (11, 0), in: $0)
        }
        for plan in unselected {
            await harness.calendar.put(plan)
        }
        let selected = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), in: SyncHarness.work)
        await harness.calendar.put(selected)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.map(\.matchDecider) == [.rules])
        #expect(await harness.calendar.allEvents.first { $0.id == selected.id }?.content.start == workout.start)
        for plan in unselected {
            #expect(await harness.calendar.allEvents.contains(plan))
        }
        // The destination is read too, but only to find the app's own events, never for plans.
        let read = await harness.calendar.readCalendarIDs
        #expect(read.contains(SyncHarness.work.id))
        #expect(read.isDisjoint(with: [SyncHarness.personal.id, SyncHarness.family.id]))
    }

    @Test("With no calendars picked, the destination and default calendars are searched")
    func emptyChoiceSearchesDefaults() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.searchCalendars = [] }
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.map(\.matchDecider) == [.rules])
        #expect(await harness.calendar.allEvents.map(\.id) == [planned.id])
        #expect(await harness.calendar.readCalendarIDs == [SyncHarness.personal.id, SyncHarness.destination.id])
    }

    @Test("\"Create separate event\" never modifies a planned event, and doesn't look for one")
    func separateEventModeLeavesPlansAlone() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.matchMode = .createSeparateEvent }
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)
        let range = DateInterval(start: SyncHarness.today((0, 0)), end: SyncHarness.now)

        let preview = try await harness.engine.run(.backfill(range, .preview))
        let commit = try await harness.engine.run(.backfill(range, .commit))
        let again = try await harness.engine.run(.changes(since: nil))

        #expect(preview.actions.map(\.matchDecider) == [nil])
        try await harness.expectSeparateEvent(for: workout, leaving: [planned], result: commit)
        #expect(again.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents.contains(planned))
        #expect(await !harness.calendar.readCalendarIDs.contains(SyncHarness.personal.id))
    }

    @Test("A wider or narrower window changes which nearby plans match", arguments: [
        (window: 30, offset: 45, matches: false),
        (window: 60, offset: 45, matches: true),
        (window: 60, offset: 90, matches: false),
        (window: 120, offset: 90, matches: true),
    ])
    func windowCanBeChanged(_ window: Int, _ offset: Int, _ matches: Bool) async throws {
        // A 30-minute run from 10:10, and a 30-minute plan that never overlaps it.
        let workout = SyncHarness.run(from: (10, 10), to: (10, 40))
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.matchWindow = TimeInterval(window * 60) }
        let start = 10 * 60 + 10 + offset
        await harness.calendar.put(SyncHarness.planned("Run", from: (0, start), to: (0, start + 30)))

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.map(\.matchDecider) == [matches ? .rules : nil])
    }

    @Test("\"Also rename\" is off by default, so a matched plan keeps the user's title")
    func renameIsOffByDefault() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        await harness.calendar.put(SyncHarness.planned("Tempo with the club", from: (10, 0), to: (11, 0)))

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(Settings().renameMatchedEvents == false)
        #expect(await harness.calendar.allEvents.map(\.content.title) == ["Tempo with the club"])
    }

    @Test("A keyword the user adds produces a rule match")
    func addedKeywordMatches() async throws {
        let ride = SyncHarness.run(from: (18, 0), to: (19, 30), type: .cycling)
        let harness = try await SyncHarness.matching(workouts: [ride]) { _ = $0.addMatchKeyword("  Chaingang ", for: .cycling) }
        await harness.calendar.put(SyncHarness.planned("Wednesday chaingang", from: (18, 0), to: (19, 30)))

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.map(\.matchDecider) == [.rules])
    }

    @Test("Blank keywords and ones the type already has aren't added again")
    func duplicateKeywordsAreIgnored() {
        var settings = Settings()

        let added = ["Parkrun Plus", "parkrun  plus", "Running", "   ", "!!"].map {
            settings.addMatchKeyword($0, for: .running)
        }

        #expect(added == [true, false, false, false, false])
        #expect(settings.matchKeywords == [.running: ["Parkrun Plus"]])

        settings.removeMatchKeyword("Parkrun Plus", for: .running)
        #expect(settings.matchKeywords.isEmpty)
    }
}

extension SyncHarness {
    /// A calendar the user shares with their family, which they never pick for matching.
    static let family = CalendarInfo(id: "family", title: "Family")
}
