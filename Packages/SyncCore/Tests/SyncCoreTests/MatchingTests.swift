import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Matching planned events")
struct MatchingTests {
    @Test("A planned run is moved to the real times, keeps its title and notes, and gains a workout section")
    func ruleMatchUpdatesPlannedEvent() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), notes: "Bring gels")
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(event.id == planned.id)
        #expect(event.calendarID == SyncHarness.personal.id)
        #expect(event.content.title == "Run")
        #expect(event.content.start == workout.start)
        #expect(event.content.end == workout.end)
        let notes = try #require(event.content.notes)
        #expect(notes.hasPrefix("Bring gels\n\n"))
        #expect(notes.contains("Duration: 55 min"))
        #expect(notes.contains("Planned: 10:00\u{2009}–\u{2009}11:00\u{202F}AM"))
        #expect(WorkoutSection.isPresent(in: notes, workoutID: workout.id))
        #expect(!notes.contains("Logged by Gainsday"))
        #expect(result.actions == [.adopt(workoutID: workout.id, eventID: planned.id, event.content, decidedBy: .rules)])

        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .adopted)
        #expect(entry.workoutID == workout.id)
        #expect(entry.eventExternalIdentifier == planned.id)
        #expect(entry.calendarID == SyncHarness.personal.id)
        #expect(entry.writtenFingerprint == event.content.fingerprint)
        #expect(entry.preUpdate == planned.content)
    }

    @Test("A planned event for a different kind of workout is left alone, and the workout gets its own event")
    func nonMatchCreatesSeparateEvent() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let planned = SyncHarness.planned("Yoga", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        try await harness.expectSeparateEvent(for: workout, leaving: [planned], result: result)
    }

    @Test("Unclear plans are left alone, and the workout gets its own event", arguments: [
        ["Gym w/ Alex"],
        ["Run", "Easy run"],
        ["Run then lift"],
    ])
    func unclearCreatesSeparateEvent(_ titles: [String]) async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let plans = titles.enumerated().map { SyncHarness.planned($1, from: (10, $0), to: (11, 0)) }
        for plan in plans {
            await harness.calendar.put(plan)
        }

        let result = try await harness.engine.run(.changes(since: nil))

        try await harness.expectSeparateEvent(for: workout, leaving: plans, result: result)
    }

    @Test("The one plan with a keyword for the workout's type wins over plans without keywords")
    func oneStrongMatchWins() async throws {
        let workout = SyncHarness.run(from: (12, 10), to: (12, 50))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let lunch = SyncHarness.planned("Lunch with Bob", from: (12, 0), to: (13, 0))
        let tempo = SyncHarness.planned("Tempo 5k", from: (12, 15), to: (13, 0))
        await harness.calendar.put(lunch)
        await harness.calendar.put(tempo)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.map(\.matchDecider) == [.rules])
        #expect(await harness.calendar.allEvents.map(\.content.title) == ["Lunch with Bob", "Tempo 5k"])
        #expect(await harness.calendar.allEvents.first { $0.id == tempo.id }?.content.start == workout.start)
        #expect(await harness.calendar.allEvents.first { $0.id == lunch.id } == lunch)
    }

    @Test("A planned event with guests is never updated, and the workout gets its own event")
    func eventsWithGuestsAreNeverUpdated() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let planned = SyncHarness.planned("Group run", from: (10, 0), to: (11, 0), attendees: 1)
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        try await harness.expectSeparateEvent(for: workout, leaving: [planned], result: result)
    }

    @Test("All-day, declined and repeating events are never matched", arguments: [
        SyncHarness.planned("Marathon training week", from: (0, 0), to: (24, 0), isAllDay: true),
        SyncHarness.planned("Run club", from: (10, 0), to: (11, 0), isDeclined: true),
        SyncHarness.planned("Run", from: (10, 0), to: (11, 0), isRecurring: true),
    ])
    func excludedEventsAreNeverMatched(_ planned: CalendarEvent) async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        try await harness.expectSeparateEvent(for: workout, leaving: [planned], result: result)
    }

    struct WindowCase: Sendable, CustomTestStringConvertible {
        /// Minutes from the workout's start to the plan's start.
        var offset: Int
        var matches: Bool
        var testDescription: String { "A plan starting \(offset) min from the workout \(matches ? "matches" : "doesn't match")" }
    }

    @Test("A plan that doesn't overlap the workout matches only when it starts within 60 minutes of it", arguments: [
        WindowCase(offset: 60, matches: true),
        WindowCase(offset: 61, matches: false),
        WindowCase(offset: -60, matches: true),
        WindowCase(offset: -61, matches: false),
    ])
    func windowBoundary(_ testCase: WindowCase) async throws {
        // A 30-minute run from 10:10, and a 30-minute plan that never overlaps it.
        let workout = SyncHarness.run(from: (10, 10), to: (10, 40))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let start = 10 * 60 + 10 + testCase.offset
        let planned = SyncHarness.planned("Run", from: (0, start), to: (0, start + 30))
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        if testCase.matches {
            #expect(result.actions.map(\.matchDecider) == [.rules])
            #expect(await harness.calendar.allEvents.map(\.id) == [planned.id])
        } else {
            try await harness.expectSeparateEvent(for: workout, leaving: [planned], result: result)
        }
    }

    @Test("A plan on the day before is never matched, even when it overlaps the workout")
    func planOnAnotherDayIsNotMatched() async throws {
        let workout = SyncHarness.run(from: (0, 20), to: (0, 50))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let planned = SyncHarness.planned("Midnight run", from: (-1, 30), to: (0, 30))
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        try await harness.expectSeparateEvent(for: workout, leaving: [planned], result: result)
    }

    @Test("The event of an earlier workout is never taken for a plan, even with the footer off")
    func otherWorkoutsEventsAreNotMatched() async throws {
        let first = SyncHarness.run(from: (9, 0), to: (9, 30))
        let second = SyncHarness.run(from: (10, 0), to: (10, 30))
        let harness = try await SyncHarness.matching(workouts: [first, second]) { $0.footerEnabled = false }

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.count == 2)
        #expect(result.actions.allSatisfy { if case .create = $0 { true } else { false } })
        #expect(await harness.calendar.allEvents.map(\.content.start) == [first.start, second.start])
        #expect(await harness.ledger.allEntries.map(\.state) == [.owned, .owned])
    }

    @Test("A plan already carrying a workout section, e.g. a copy of a matched event, isn't matched, so the plan kept in the ledger never holds workout data")
    func planWithWorkoutSectionIsNotMatched() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let copied = WorkoutSection.replacing(in: "Bring gels", with: "Distance: 10.02 km", workoutID: UUID())
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), notes: copied)
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        try await harness.expectSeparateEvent(for: workout, leaving: [planned], result: result)
        #expect(await harness.ledger.allEntries.allSatisfy { $0.preUpdate == nil })
    }

    @Test("Plans in the destination calendar are found too")
    func destinationCalendarIsSearched() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), in: SyncHarness.destination)
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.map(\.matchDecider) == [.rules])
        #expect(await harness.calendar.allEvents.map(\.id) == [planned.id])
    }

    @Test("Only the destination and default calendars are searched, unless the user picks others")
    func onlySearchCalendarsAreSearched() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), in: SyncHarness.work)
        let byDefault = try await SyncHarness.matching(workouts: [workout])
        await byDefault.calendar.put(planned)
        let picked = try await SyncHarness.matching(workouts: [workout]) {
            $0.searchCalendars = [CalendarReference(id: SyncHarness.work.id, title: SyncHarness.work.title)]
        }
        await picked.calendar.put(planned)

        let defaultResult = try await byDefault.engine.run(.changes(since: nil))
        let pickedResult = try await picked.engine.run(.changes(since: nil))

        try await byDefault.expectSeparateEvent(for: workout, leaving: [planned], result: defaultResult)
        #expect(pickedResult.actions.map(\.matchDecider) == [.rules])
        #expect(await picked.calendar.allEvents.map(\.id) == [planned.id])
    }

    @Test("With matching off, in separate-event mode, or with add-only access, plans are left alone")
    func matchingCanBeOff() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0))
        let off = try await SyncHarness.matching(workouts: [workout]) { $0.matchingEnabled = false }
        let separate = try await SyncHarness.matching(workouts: [workout]) { $0.matchMode = .createSeparateEvent }
        let addOnly = try await SyncHarness.matching(workouts: [workout])

        for harness in [off, separate, addOnly] {
            await harness.calendar.put(planned)
        }
        await addOnly.calendar.setAccessMode(.addOnly)

        for harness in [off, separate, addOnly] {
            let result = try await harness.engine.run(.changes(since: nil))
            #expect(result.actions.map(\.matchDecider) == [nil])
            #expect(await harness.calendar.allEvents.count == 2)
            #expect(await harness.calendar.allEvents.contains(planned))
        }
    }

    @Test("Calendars are refreshed before matching, so a plan made elsewhere moments ago can be seen")
    func calendarsAreRefreshedFirst() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.refreshCount == 1)
    }

    @Test("Calendars are refreshed once per pass, however many workouts it matches")
    func calendarsAreRefreshedOncePerPass() async throws {
        let workouts = [
            SyncHarness.run(from: (7, 0), to: (7, 30)),
            SyncHarness.run(from: (10, 10), to: (11, 5)),
            SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining),
        ]
        let harness = try await SyncHarness.matching(workouts: workouts)

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.count == 3)
        #expect(await harness.calendar.refreshCount == 1)
    }

    @Test("The user's own keywords decide matches too")
    func userKeywordsMatch() async throws {
        let workout = SyncHarness.run(from: (18, 0), to: (18, 45))
        let planned = SyncHarness.planned("Tuesday Club", from: (18, 0), to: (19, 0))
        let builtInOnly = try await SyncHarness.matching(workouts: [workout])
        await builtInOnly.calendar.put(planned)
        let withKeyword = try await SyncHarness.matching(workouts: [workout]) { $0.matchKeywords = [.running: ["tuesday club"]] }
        await withKeyword.calendar.put(planned)

        let builtInResult = try await builtInOnly.engine.run(.changes(since: nil))
        let keywordResult = try await withKeyword.engine.run(.changes(since: nil))

        try await builtInOnly.expectSeparateEvent(for: workout, leaving: [planned], result: builtInResult)
        #expect(keywordResult.actions.map(\.matchDecider) == [.rules])
    }

    @Test("With \"Also rename\" on, the plan takes the title template's title")
    func renameUsesTemplateTitle() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.renameMatchedEvents = true }
        await harness.calendar.put(SyncHarness.planned("Run", from: (10, 0), to: (11, 0)))

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.map(\.content.title) == ["🏃 Running · 3.11 mi"])
    }

    @Test("The log entry for a match keeps the plan's title and says the rules decided")
    func matchIsLoggedAsRuleDecision() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let planned = SyncHarness.planned("Run with Sam", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        let entry = try #require(await harness.activityLog.entries.first)
        #expect(await harness.activityLog.entries.count == 1)
        #expect(entry.action == result.actions.first)
        #expect(entry.action.matchDecider == .rules)
        #expect(entry.title == "Run with Sam")
        #expect(entry.eventID == planned.id)
        #expect(entry.workoutStart == workout.start)
        #expect(entry.activityType == .running)
    }

    @Test("A backfill preview lists the match without changing the plan, and the commit makes it")
    func backfillPreviewsMatch() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)
        let range = DateInterval(start: SyncHarness.today((0, 0)), end: SyncHarness.now)

        let preview = try await harness.engine.run(.backfill(range, .preview))
        #expect(await harness.calendar.allEvents == [planned])
        #expect(await harness.ledger.allEntries.isEmpty)

        let commit = try await harness.engine.run(.backfill(range, .commit))
        #expect(commit.actions == preview.actions)
        #expect(commit.actions.map(\.matchDecider) == [.rules])
        #expect(await harness.calendar.allEvents.map(\.content.start) == [workout.start])
    }

    @Test("Copies of one workout from the Watch and Strava adopt one plan together")
    func clusterAdoptsOnePlan() async throws {
        let watch = SyncHarness.run(from: (10, 10), to: (11, 5))
        let strava = SyncHarness.stravaCopy(of: watch)
        let harness = try await SyncHarness.matching(workouts: [watch, strava])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.map(\.matchDecider) == [.rules])
        #expect(await harness.calendar.allEvents.map(\.id) == [planned.id])
        #expect(await harness.calendar.allEvents.first?.content.start == watch.start)
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.workoutID == watch.id)
        #expect(entry.memberIDs == [watch.id, strava.id])
    }

    @Test("A workout already matched is skipped by later passes")
    func matchedWorkoutIsNotMatchedAgain() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout])
        await harness.calendar.put(SyncHarness.planned("Run", from: (10, 0), to: (11, 0)))
        _ = try await harness.engine.run(.changes(since: nil))
        let afterFirst = await harness.calendar.allEvents

        let again = try await harness.engine.run(.changes(since: nil))

        #expect(again.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents == afterFirst)
        #expect(await harness.ledger.allEntries.map(\.state) == [.adopted])
    }
}

extension SyncHarness {
    /// The user's default calendar, where they keep their plans.
    static let personal = CalendarInfo(id: "personal", title: "Personal")
    static let work = CalendarInfo(id: "work", title: "Work")

    /// A harness with matching turned on and a default calendar besides the destination.
    static func matching(workouts: [Workout] = [], configure: (inout Settings) -> Void = { _ in }) async throws -> SyncHarness {
        var settings = defaultSettings
        settings.matchingEnabled = true
        configure(&settings)
        let harness = SyncHarness(workouts: workouts, settings: settings)
        await harness.calendar.addCalendar(personal)
        await harness.calendar.addCalendar(work)
        await harness.calendar.setDefaultCalendar(id: personal.id)
        return harness
    }

    /// A time today, in the harness clock's UTC calendar.
    static func today(_ time: (hour: Int, minute: Int)) -> Date {
        FixedClock(now: now).calendar.startOfDay(for: now)
            .addingTimeInterval(TimeInterval(time.hour * 3600 + time.minute * 60))
    }

    static func run(from start: (Int, Int), to end: (Int, Int), type: WorkoutActivityType = .running) -> Workout {
        Workout(
            activityType: type,
            start: today(start),
            end: today(end),
            source: watch,
            metrics: WorkoutMetrics(distanceMeters: 5_000, averageHeartRate: 150)
        )
    }

    /// An event the user planned themselves.
    static func planned(
        _ title: String,
        from start: (Int, Int),
        to end: (Int, Int),
        in calendar: CalendarInfo = personal,
        notes: String? = nil,
        attendees: Int = 0,
        isAllDay: Bool = false,
        isDeclined: Bool = false,
        isRecurring: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: "planned-\(title)-\(start.0):\(start.1)",
            calendarID: calendar.id,
            content: EventContent(title: title, start: today(start), end: today(end), notes: notes),
            isAllDay: isAllDay,
            attendeeCount: attendees,
            isDeclinedByUser: isDeclined,
            isRecurring: isRecurring
        )
    }
}

extension SyncHarness {
    /// Checks the workout got its own owned event and every plan is as it was.
    func expectSeparateEvent(for workout: Workout, leaving plans: [CalendarEvent], result: SyncResult) async throws {
        let created = try #require(result.actions.first)
        guard case .create(let workoutID, let draft) = created, result.actions.count == 1 else {
            Issue.record("Expected one create, got \(result.actions)")
            return
        }
        #expect(workoutID == workout.id)
        #expect(draft.calendarID == Self.destination.id)
        let events = await calendar.allEvents
        #expect(events.count == plans.count + 1)
        for plan in plans {
            #expect(events.contains(plan))
        }
        #expect(await ledger.allEntries.map(\.state) == [.owned])
    }
}
