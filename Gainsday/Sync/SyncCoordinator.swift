import Foundation
import Observation
import SyncCore
import UserNotifications

/// Wires the sync engine to the real adapters, runs passes and keeps the state the UI shows.
@Observable
final class SyncCoordinator {
    struct Pass {
        var finishedAt: Date
    }

    private(set) var settings = Settings()
    private(set) var hasLoaded = false
    /// Health and calendar permissions don't survive a reinstall, though settings
    /// restored from iCloud do, so setup runs once on every install.
    private(set) var hasFinishedSetupOnThisDevice = UserDefaults.standard.bool(forKey: setupKey)
    /// How many passes or backfills are running or queued in `runner`.
    var runningPasses = 0
    var isSyncing: Bool { runningPasses > 0 }
    /// A pass found the phone locked. It runs again once the phone is unlocked.
    var isWaitingForUnlock = false
    var lastPass: Pass?
    var lastError: String?
    /// The activity log, newest first.
    private(set) var activityLog: [ActivityLogEntry] = []
    /// Add-only access greys out features that need to read or change events.
    private(set) var calendarAccess = AccessMode.none

    let health: HealthKitWorkoutSource
    let calendar: EventKitCalendarStore
    private let settingsStore: CloudSettingsStore
    let cloudImport: CloudImportMonitor
    private let activityLogStore: FileActivityLogStore
    let clock = SystemClock()
    private let notifier = LocalNotifier()
    let engine: SyncEngine
    /// Runs passes one at a time, so overlapping triggers create no duplicates.
    let runner: SyncRunner
    /// How long the app waits for a pass, including the iCloud import wait,
    /// before showing an error.
    static let passTimeout: Duration = .seconds(90)
    /// How long launch waits for settings, calendar access and the activity log before
    /// showing the app anyway. What arrives later still updates it.
    static let loadTimeout: Duration = .seconds(10)
    private static let setupKey = "hasFinishedSetupOnThisDevice"

    var isSetUp: Bool {
        hasFinishedSetupOnThisDevice && settings.destinationCalendar != nil && settings.syncStartDate != nil
    }

    /// `cloudImport` must be made before the ledger's container, so it sees the first import.
    init(ledger: any Ledger, cloudImport: CloudImportMonitor = CloudImportMonitor()) {
        self.cloudImport = cloudImport
        health = HealthKitWorkoutSource()
        calendar = EventKitCalendarStore()
        settingsStore = CloudSettingsStore()
        activityLogStore = FileActivityLogStore()
        engine = SyncEngine(
            workouts: health,
            calendar: calendar,
            ledger: ledger,
            settings: settingsStore,
            judge: OnDeviceMatchJudge(),
            clock: clock,
            notifier: notifier,
            activityLog: activityLogStore
        )
        runner = SyncRunner(engine: engine, anchors: AnchorStore())
        UNUserNotificationCenter.current().delegate = notifier
    }

    /// Loads the state the UI shows. A system service that hangs can't keep the app on
    /// its loading screen: after `loadTimeout` it shows what it has, and an error.
    func load() async {
        do {
            try await withTimeout(Self.loadTimeout) { await self.loadState() }
        } catch {
            lastError = error.localizedDescription
        }
        hasLoaded = true
    }

    private func loadState() async {
        settings = await settingsStore.load()
        calendarAccess = await calendar.accessMode()
        await refreshActivityLog()
        // The setup flag can come back from a device backup, and access can be revoked
        // in Settings. Either way, setup has to ask again before syncing can work.
        if hasFinishedSetupOnThisDevice, calendarAccess == .none {
            await engine.report(.calendarAccessRevoked)
            forgetSetup()
        }
    }

    /// Reloads settings whenever iCloud delivers a change, since settings restored
    /// after a reinstall can arrive after the app has opened.
    func watchCloudSettings() async {
        for await _ in settingsStore.externalChanges() {
            await load()
        }
    }

    /// Saves the destination and setup's other `choices`, and starts syncing workouts from
    /// now on. A sync start date restored from iCloud is kept, so a reinstall doesn't skip workouts.
    func finishSetup(destination: CalendarInfo, choices: @escaping @Sendable (inout Settings) -> Void = { _ in }) async {
        let reference = CalendarReference(id: destination.id, title: destination.title)
        let now = clock.now
        // Waits for settings restored from iCloud, so their start date is the one kept.
        settings = await settingsStore.edit { settings in
            choices(&settings)
            settings.destinationCalendar = reference
            settings.syncStartDate = settings.syncStartDate ?? now
        }
        UserDefaults.standard.set(true, forKey: Self.setupKey)
        hasFinishedSetupOnThisDevice = true
        await notifier.requestAuthorization()
        await sync()
    }

    /// Changes settings now and backs them up to iCloud, on top of any still being restored.
    func updateSettings(_ change: @escaping @Sendable (inout Settings) -> Void) {
        change(&settings)
        Task { await settingsStore.edit(change) }
    }

    /// Runs a catch-up pass from the stored anchor. Does nothing before setup. If a
    /// pass is already running, waits for it and then runs one more, so a workout
    /// that arrived during it isn't missed. Shows an error after `passTimeout`.
    func sync() async {
        runningPasses += 1
        defer { runningPasses -= 1 }
        do {
            try await withTimeout(Self.passTimeout) { await self.runPass() }
        } catch is CancellationError {
            // The system stopped a background pass. The next one picks up from the anchor.
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// A pass that runs past its timeout still records its result when it finishes.
    private func runPass() async {
        await load()
        guard isSetUp else { return }
        // After a reinstall, give the ledger a chance to come back from iCloud first.
        _ = await cloudImport.waitForInitialImport()
        do {
            _ = try await runner.syncChanges()
            isWaitingForUnlock = false
            lastPass = Pass(finishedAt: clock.now)
            // A pass after upgrading from add-only access names the default calendar.
            settings = await settingsStore.load()
            lastError = nil
        } catch is CancellationError {
            // Stopped between workouts. The anchor didn't move, so the next pass finishes it.
        } catch WorkoutSourceError.locked {
            isWaitingForUnlock = true
        } catch CalendarStoreError.calendarNotFound(let id) where id == settings.destinationCalendar?.id {
            // The destination was deleted. Setup lets the user choose another.
            forgetSetup()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshActivityLog()
    }

    /// Undoes an activity log entry. It counts as a pass, so it never runs alongside one.
    /// Undoing an update to a planned event needs the user's choice for the workout.
    func undo(_ entry: ActivityLogEntry, choice: ActivityLogEntry.PlannedEventUndoChoice? = nil) async throws {
        runningPasses += 1
        defer { runningPasses -= 1 }
        try await withTimeout(Self.passTimeout) {
            if let choice {
                try await self.runner.undo(entryID: entry.id, choice: choice)
            } else {
                try await self.runner.undo(entryID: entry.id)
            }
        }
        await refreshActivityLog()
    }

    func refreshActivityLog() async {
        activityLog = (try? await activityLogStore.load()) ?? []
    }

    private func forgetSetup() {
        UserDefaults.standard.removeObject(forKey: Self.setupKey)
        hasFinishedSetupOnThisDevice = false
    }
}
