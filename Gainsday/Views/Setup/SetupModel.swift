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
    /// The user chose add-only access, so the system chooser picks the calendar.
    var isAddOnly = false
    var isChoosingAddOnlyCalendar = false
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

    /// Shows Health's permission sheet. Returns false if it couldn't be shown.
    func requestHealthAccess(_ coordinator: SyncCoordinator) async -> Bool {
        do {
            try await coordinator.health.requestAuthorization()
            healthRequested = true
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

    /// Add-only access can't list calendars, so the system chooser picks one.
    func requestAddOnlyAccess(_ coordinator: SyncCoordinator) async {
        do {
            calendarAccessDenied = !(try await coordinator.calendar.requestAddOnlyAccess())
            guard !calendarAccessDenied else { return }
            isAddOnly = true
            isChoosingAddOnlyCalendar = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Keeps the calendar picked in the system chooser, or the previous one if it was cancelled.
    func finishChoosingAddOnlyCalendar(_ chosen: CalendarInfo?) {
        if let chosen {
            calendars = [chosen]
            selectedCalendarID = chosen.id
        }
        isChoosingAddOnlyCalendar = false
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

    func startSyncing(_ coordinator: SyncCoordinator) async {
        guard let selectedCalendar else { return }
        isStarting = true
        await coordinator.finishSetup(destination: selectedCalendar)
        if addsPastWeek { await coordinator.backfillPastWeek() }
        isStarting = false
    }
}
