import Foundation
import SwiftData
import SyncCore
import Testing
@testable import Gainsday

/// App Review guideline 5.1.3(ii): no personal health information in iCloud. The
/// ledger is the app's only iCloud data; the activity log stays on the device.
@Suite("Ledger privacy")
struct LedgerPrivacyTests {
    @Test("A workout synced with the Detailed template leaves none of its metrics or event text in the iCloud ledger")
    func ledgerHoldsNoHealthData() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ledger-privacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelConfiguration(url: directory.appending(path: "Ledger.store"), cloudKitDatabase: .none)
        let ledger = SwiftDataLedger(modelContainer: try ModelContainer(for: LedgerRecord.self, configurations: store))
        let end = Date.now.addingTimeInterval(-10 * 60)
        let workout = Workout(
            activityType: .running,
            start: end.addingTimeInterval(-62 * 60),
            end: end,
            source: WorkoutSourceApp(bundleIdentifier: "com.apple.health", name: "Apple Watch"),
            metrics: WorkoutMetrics(
                distanceMeters: 10_020,
                activeEnergyKilocalories: 612,
                averageHeartRate: 152,
                maxHeartRate: 171,
                elevationAscendedMeters: 87
            )
        )
        let calendar = PrivacyTestCalendar()
        let engine = SyncEngine(
            workouts: PrivacyTestWorkouts(workout: workout),
            calendar: calendar,
            ledger: ledger,
            settings: PrivacyTestSettings(Settings(
                destinationCalendar: CalendarReference(id: PrivacyTestCalendar.destination.id, title: PrivacyTestCalendar.destination.title),
                template: StarterTemplate.detailed.template,
                syncStartDate: end.addingTimeInterval(-24 * 60 * 60)
            )),
            judge: PrivacyTestJudge(),
            clock: SystemClock(),
            notifier: PrivacyTestNotifier(),
            activityLog: FileActivityLogStore(url: directory.appending(path: "ActivityLog.json"))
        )

        _ = try await engine.run(.changes(since: nil))

        let event = try #require(await calendar.events.first)
        let notes = try #require(event.content.notes)
        #expect(notes.contains("152"), "The template should have written the heart rate")
        let entry = try #require(try await ledger.entries(forWorkout: workout.id).first)
        #expect(entry.writtenFingerprint == event.content.fingerprint)
        #expect(entry.preUpdate == nil)

        // Every byte SwiftData keeps for the ledger, whatever the property.
        var stored = Data()
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where file.lastPathComponent.hasPrefix("Ledger.store") {
            stored.append(try Data(contentsOf: file))
        }
        let fingerprint = try #require(entry.writtenFingerprint?.storageValue)
        #expect(stored.range(of: Data(fingerprint.utf8)) != nil, "The check should read where the ledger is stored")
        let lines = notes.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let values = lines.compactMap { $0.split(separator: ": ", maxSplits: 1).last.map(String.init) }
        for text in [event.content.title, notes] + lines + values {
            #expect(stored.range(of: Data(text.utf8)) == nil, "The ledger holds \"\(text)\"")
        }
    }
}

private actor PrivacyTestCalendar: CalendarStore {
    static let destination = CalendarInfo(id: "workouts", title: "Workouts")
    private(set) var events: [CalendarEvent] = []

    func accessMode() async -> AccessMode { .full }
    func writableCalendars() async throws -> [CalendarInfo] { [Self.destination] }
    func events(in interval: DateInterval, calendarIDs: Set<String>) async throws -> [CalendarEvent] {
        events.filter { calendarIDs.contains($0.calendarID) && $0.content.start < interval.end && $0.content.end > interval.start }
    }
    func event(withID id: String) async throws -> CalendarEvent? { events.first { $0.id == id } }
    func create(_ draft: EventDraft) async throws -> CalendarEvent {
        let event = CalendarEvent(id: UUID().uuidString, calendarID: draft.calendarID, content: draft.content, availability: draft.availability)
        events.append(event)
        return event
    }
    func update(eventID: String, to content: EventContent) async throws -> CalendarEvent {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { throw CalendarStoreError.eventNotFound(id: eventID) }
        events[index].content = content
        return events[index]
    }
    func delete(eventID: String) async throws { events.removeAll { $0.id == eventID } }
    func refreshSources() async {}
    func defaultCalendarID() async -> String? { nil }
}

private nonisolated struct PrivacyTestWorkouts: WorkoutSource {
    let workout: Workout

    func changes(since anchor: WorkoutAnchor?) async throws -> WorkoutChanges {
        WorkoutChanges(added: [workout], deletedIDs: [], anchor: WorkoutAnchor(data: Data()))
    }
    func workouts(in interval: DateInterval) async throws -> [Workout] {
        interval.intersects(workout.interval) ? [workout] : []
    }
    func recentWorkouts(limit: Int) async throws -> [Workout] { [workout] }
}

private actor PrivacyTestSettings: SettingsStore {
    private var settings: Settings

    init(_ settings: Settings) {
        self.settings = settings
    }

    func load() async -> Settings { settings }
    func save(_ settings: Settings) async { self.settings = settings }
    func edit(_ change: @escaping @Sendable (inout Settings) -> Void) async -> Settings {
        change(&settings)
        return settings
    }
}

private nonisolated struct PrivacyTestJudge: MatchJudge {
    func availability() async -> MatchJudgeAvailability { .unavailable }
    func judge(_ workout: Workout, candidates: [CalendarEvent]) async throws -> MatchJudgement {
        MatchJudgement(chosenIndex: nil, confidence: 0)
    }
}

private nonisolated struct PrivacyTestNotifier: ProblemNotifier {
    func notifiedProblems() async -> Set<Problem> { [] }
    func notify(_ problem: Problem) async {}
    func withdraw(_ problem: Problem) async {}
}
