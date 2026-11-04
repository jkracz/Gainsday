import Foundation
import Observation
import SyncCore

/// What the user has done so far in setup, shared by its steps.
@Observable
final class SetupModel {
    /// The steps shown after the welcome screen.
    var path: [SetupStep] = []
    var healthRequested = false
    var calendars: [CalendarInfo]?
    var calendarColors: [String: CalendarColor] = [:]
    var selectedCalendarID: String?
    var calendarAccessDenied = false
    /// The user chose add-only access, so events go to their default calendar.
    var isAddOnly = false
    /// Nil preserves the restored setting until the user chooses or starts syncing with full access.
    var enablesMatching: Bool?
    /// Whether Start Syncing also adds the past week's workouts.
    var addsPastWeek = true
    var isStarting = false
    var errorMessage: String?

    var selectedCalendar: CalendarInfo? {
        calendars?.first { $0.id == selectedCalendarID }
    }

    func showStep(after step: SetupStep) {
        errorMessage = nil
        if let next = step.next {
            path.append(next)
        }
    }

    /// Shows Health's permission sheet, then restarts the workout observer and turns
    /// on background delivery, which both fail until access has been asked for.
    /// Returns false if it couldn't be shown.
    func requestHealthAccess(_ coordinator: SyncCoordinator) async -> Bool {
        do {
            try await coordinator.health.requestAuthorization()
            healthRequested = true
            coordinator.health.restartObservingWorkouts()
            await coordinator.enableBackgroundDelivery()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func requestCalendarAccess(_ coordinator: SyncCoordinator) async {
        do {
            calendarAccessDenied = !(try await coordinator.calendar.requestFullAccess())
            guard !calendarAccessDenied else { return }
            await refreshCalendars(coordinator)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// With add-only access iOS adds events to the user's default calendar and doesn't
    /// let the app choose another, so that's the destination.
    func requestAddOnlyAccess(_ coordinator: SyncCoordinator) async {
        do {
            calendarAccessDenied = !(try await coordinator.calendar.requestAddOnlyAccess())
            guard !calendarAccessDenied else { return }
            isAddOnly = true
            let defaultCalendar = CalendarReference.defaultCalendar
            calendars = [CalendarInfo(id: defaultCalendar.id, title: defaultCalendar.displayTitle)]
            selectedCalendarID = defaultCalendar.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads the list, keeping the selection if that calendar still exists.
    func refreshCalendars(_ coordinator: SyncCoordinator) async {
        do {
            calendars = try await coordinator.calendar.writableCalendars()
            calendarColors = await coordinator.calendar.calendarColors()
            if selectedCalendar == nil { selectRestoredCalendar(coordinator) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Preselects the calendar restored from iCloud after a reinstall, if it's in the list.
    func selectRestoredCalendar(_ coordinator: SyncCoordinator) {
        let restoredID = coordinator.settings.destinationCalendar?.id
        selectedCalendarID = calendars?.first { $0.id == restoredID }?.id
    }

    /// The matching answer to show: the user's, or else the setting, which is off on a fresh install.
    func showsMatchingOn(_ settings: Settings) -> Bool {
        enablesMatching ?? settings.matchingEnabled
    }

    /// Setup's choices, as an edit for `finishSetup` to save along with the destination.
    var choices: @Sendable (inout Settings) -> Void {
        let enablesMatching = enablesMatching
        return { settings in
            if let enablesMatching { settings.matchingEnabled = enablesMatching }
        }
    }

    func startSyncing(_ coordinator: SyncCoordinator) async {
        guard let selectedCalendar else { return }
        isStarting = true
        // Pin the displayed choice before a late iCloud restore can change it.
        if !isAddOnly { enablesMatching = showsMatchingOn(coordinator.settings) }
        await coordinator.finishSetup(destination: selectedCalendar, choices: choices)
        if enablesMatching == true { MatchingExplanation.hasTurnedOnMatching = true }
        if addsPastWeek { await coordinator.backfillPastWeek() }
        isStarting = false
    }
}
