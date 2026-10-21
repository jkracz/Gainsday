import Foundation

/// What to do with a workout once its planned-event candidates have been judged. [v1.1]
enum MatchDecision {
    /// Update this planned event with the workout and adopt it.
    case adopt(CalendarEvent, decidedBy: MatchDecider)
    /// Leave the plans alone and create a separate owned event.
    case separateEvent
}

/// Matching planned events: a workout the user put in their calendar beforehand
/// updates that event in place instead of getting a separate one. [v1.1]
extension SyncEngine {
    /// Finds the event the user planned for a workout that has no event yet, and adopts
    /// it: the event moves to the workout's times, keeps its title, and gains a workout
    /// section in its notes. Returns nil when the workout should get a separate owned
    /// event instead: matching is off or in "create separate event" mode, the app can't
    /// read calendars, nothing matches, the match is unclear, or the event has guests.
    func matchPlannedEvent(for workout: Workout, destination calendarID: String, settings: Settings, composer: EventComposer) async throws -> SyncAction? {
        guard settings.matchingEnabled, settings.matchMode == .updatePlannedEvent,
              await calendar.accessMode() == .full else { return nil }
        // A plan added on the web moments ago may not have reached the phone yet.
        await calendar.refreshSources()
        let candidates = try await plannedEventCandidates(for: workout, destination: calendarID, settings: settings)

        let decision: MatchDecision
        switch MatchRules(for: workout.activityType, userKeywords: settings.matchKeywords).outcome(for: candidates) {
        case .match(let event):
            decision = .adopt(event, decidedBy: .rules)
        case .noMatch:
            decision = .separateEvent
        case .unclear(let unclear):
            decision = try await decideUnclearMatch(for: workout, among: unclear, settings: settings)
        }

        switch decision {
        case .adopt(let event, let decider):
            // Changing an event with guests can email every one of them, so only the
            // user's own events are updated, whatever decided the match.
            guard event.attendeeCount == 0 else { return nil }
            return try await adopt(event, for: workout, decidedBy: decider, settings: settings, composer: composer)
        case .separateEvent:
            return nil
        }
    }

    /// The one place a match the rules found unclear is decided. Until the on-device
    /// model can be asked, each one gets a separate event, so a wrong update never
    /// happens silently.
    func decideUnclearMatch(for workout: Workout, among candidates: [CalendarEvent], settings: Settings) async throws -> MatchDecision {
        .separateEvent
    }

    /// Events in the search calendars that could be the plan for the workout: on the
    /// same day, overlapping it or starting within the match window of its start. All-day,
    /// declined and repeating events are left out, and so are events the app wrote or
    /// already links to a workout.
    func plannedEventCandidates(for workout: Workout, destination calendarID: String, settings: Settings) async throws -> [CalendarEvent] {
        let calendarIDs = try await searchCalendarIDs(destination: calendarID, settings: settings)
        guard !calendarIDs.isEmpty, let day = clock.calendar.dateInterval(of: .day, for: workout.start) else { return [] }
        let claimed = Set(try await ledger.entries(in: day)
            .filter { $0.state != .tombstoned }
            .compactMap(\.eventExternalIdentifier))
        return try await calendar.events(in: day, calendarIDs: calendarIDs)
            .filter { event in
                let planned = event.content
                let overlaps = planned.start < workout.end && planned.end > workout.start
                let startsNearby = abs(planned.start.timeIntervalSince(workout.start)) <= settings.matchWindow
                return !event.isAllDay && !event.isDeclinedByUser && !event.isRecurring
                    && !claimed.contains(event.id)
                    && !Footer.isAnyPresent(in: planned.notes) && !WorkoutSection.isAnyPresent(in: planned.notes)
                    && clock.calendar.isDate(planned.start, inSameDayAs: workout.start)
                    && (overlaps || startsNearby)
            }
            .sorted { ($0.content.start, $0.id) < ($1.content.start, $1.id) }
    }

    /// The calendars the user lets the app search, or by default the destination plus
    /// the default calendar. Only calendars the app can write to are searched.
    private func searchCalendarIDs(destination calendarID: String, settings: Settings) async throws -> Set<String> {
        var searched = Set(settings.searchCalendars?.map(\.id) ?? [calendarID])
        if settings.searchCalendars == nil, let defaultID = await calendar.defaultCalendarID() {
            searched.insert(defaultID)
        }
        return searched.intersection(try await calendar.writableCalendars().map(\.id))
    }

    /// Moves the planned event to the workout's times and puts the workout section in its
    /// notes, keeping the user's title and notes. The event before the update is kept in
    /// the ledger, for Undo and for when the workout is deleted.
    private func adopt(_ event: CalendarEvent, for workout: Workout, decidedBy decider: MatchDecider, settings: Settings, composer: EventComposer) async throws -> SyncAction {
        var content = event.content
        content.start = workout.start
        content.end = workout.end
        if settings.renameMatchedEvents {
            content.title = composer.content(for: workout).title
        }
        content.notes = WorkoutSection.replacing(
            in: event.content.notes,
            with: composer.workoutSectionBody(for: workout, planned: event.content),
            workoutID: workout.id
        )
        let updated = try await calendar.update(eventID: event.id, to: content)
        let now = clock.now
        do {
            try await ledger.save(LedgerEntry(
                workoutID: workout.id,
                workoutStart: workout.start,
                workoutEnd: workout.end,
                state: .adopted,
                eventExternalIdentifier: updated.id,
                calendarID: updated.calendarID,
                written: updated.content,
                preUpdate: event.content,
                createdAt: now,
                updatedAt: now,
                activityType: workout.activityType
            ))
        } catch {
            // With no ledger entry, the app would lose track of the change. Put the plan
            // back when possible. The save error is the one worth reporting.
            _ = try? await calendar.update(eventID: updated.id, to: event.content)
            throw error
        }
        return .adopt(workoutID: workout.id, eventID: updated.id, updated.content, decidedBy: decider)
    }
}

extension EventComposer {
    /// What goes between an adopted event's section markers: the rendered notes template,
    /// then the times the user planned, e.g. "Planned: 3:00 – 4:00 PM". The footer is
    /// never added, since the section's end marker does its job.
    func workoutSectionBody(for workout: Workout, planned: EventContent) -> String {
        let notes = renderer.notes(settings.template(for: workout.activityType).notes, for: workout)
        let times = Date.IntervalFormatStyle(
            date: .omitted,
            time: .shortened,
            locale: renderer.locale,
            calendar: renderer.calendar,
            timeZone: renderer.calendar.timeZone
        )
        let plannedLine = "Planned: " + (planned.start..<max(planned.start, planned.end)).formatted(times)
        return [notes, plannedLine].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
