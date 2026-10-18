import Foundation
import Observation
import SyncCore

/// Wires the sync engine to the real adapters, runs passes and keeps the state the UI shows.
@Observable
final class SyncCoordinator {
    struct Pass {
        var finishedAt: Date
        var createdCount: Int
    }

    private(set) var settings = Settings()
    private(set) var hasLoaded = false
    /// Health and calendar permissions don't survive a reinstall, though settings
    /// restored from iCloud do, so setup runs once on every install.
    private(set) var hasFinishedSetupOnThisDevice = UserDefaults.standard.bool(forKey: setupKey)
    private(set) var isSyncing = false
    private(set) var lastPass: Pass?
    private(set) var lastError: String?

    let health: HealthKitWorkoutSource
    let calendar: EventKitCalendarStore
    private let settingsStore: CloudSettingsStore
    private let anchors: AnchorStore
    private let clock = SystemClock()
    private let engine: SyncEngine
    private static let setupKey = "hasFinishedSetupOnThisDevice"

    var isSetUp: Bool {
        hasFinishedSetupOnThisDevice && settings.destinationCalendar != nil && settings.syncStartDate != nil
    }

    init(ledger: any Ledger) {
        health = HealthKitWorkoutSource()
        calendar = EventKitCalendarStore()
        settingsStore = CloudSettingsStore()
        anchors = AnchorStore()
        engine = SyncEngine(
            workouts: health,
            calendar: calendar,
            ledger: ledger,
            settings: settingsStore,
            judge: UnavailableMatchJudge(),
            clock: clock
        )
    }

    func load() async {
        settings = await settingsStore.load()
        hasLoaded = true
    }

    /// Saves the destination and starts syncing workouts from now on. A sync start
    /// date restored from iCloud is kept, so a reinstall doesn't skip workouts.
    func finishSetup(destination: CalendarInfo) async {
        settings.destinationCalendar = CalendarReference(id: destination.id, title: destination.title)
        settings.syncStartDate = settings.syncStartDate ?? clock.now
        await settingsStore.save(settings)
        UserDefaults.standard.set(true, forKey: Self.setupKey)
        hasFinishedSetupOnThisDevice = true
        await sync()
    }

    /// Runs a catch-up pass from the stored anchor. Does nothing before setup, or
    /// while another pass is running, so overlapping triggers create no duplicates.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        await load()
        guard isSetUp else { return }
        do {
            let result = try await engine.run(.changes(since: anchors.load()))
            if let anchor = result.nextAnchor {
                anchors.save(anchor)
            }
            let createdCount = result.actions.count { if case .create = $0 { true } else { false } }
            lastPass = Pass(finishedAt: clock.now, createdCount: createdCount)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
