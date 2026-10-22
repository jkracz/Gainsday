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
    var selectedCalendarID: String?
    var calendarAccessDenied = false
    /// The user chose add-only access, so events go to their default calendar.
    var isAddOnly = false
    /// Whether workouts update matching planned events. Nil until the matching step's
    /// Continue, and when that step is skipped, which leaves the setting as it is.
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
        var next = step.next
        while let skipped = next, !isShown(skipped) {
            next = skipped.next
        }
        if let next {
            path.append(next)
        }
    }

    /// Matching needs to read the user's events, so add-only access skips its step.
    private func isShown(_ step: SetupStep) -> Bool {
        step != .matching || !isAddOnly
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
        await coordinator.finishSetup(destination: selectedCalendar, choices: choices)
        if enablesMatching == true { MatchingExplanation.hasTurnedOnMatching = true }
        if addsPastWeek { await coordinator.backfillPastWeek() }
        isStarting = false
    }
}
