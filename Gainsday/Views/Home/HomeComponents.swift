import SwiftUI
import SyncCore
import UIKit

/// Sync progress and the destination calendar.
struct SyncStatusLine: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if coordinator.isSyncing {
                    ProgressView().controlSize(.mini)
                    Text("Syncing…")
                } else if coordinator.isWaitingForICloudImport, let waiting = WaitingForICloudImport().errorDescription {
                    Image(systemName: "icloud").accessibilityHidden(true)
                    Text(verbatim: waiting)
                } else {
                    Image(systemName: coordinator.lastError == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(coordinator.lastError == nil ? Color(.positive) : Color(.danger))
                        .accessibilityHidden(true)
                    if let pass = coordinator.lastPass {
                        Text("Synced \(pass.finishedAt.formatted(.relative(presentation: .named))) to \(calendarName)")
                    } else {
                        Text("Adding workouts to \(calendarName)")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color(.inkSecondary))
        }
    }

    private var calendarName: Text {
        let title = coordinator.settings.destinationCalendar?.displayTitle ?? ""
        return Text(verbatim: title).fontWeight(.semibold).foregroundStyle(Color(.ink))
    }
}

extension Color {
    /// Text on volt, which is light in both modes.
    nonisolated static let onVolt = Color(red: 0.055, green: 0.059, blue: 0.039)

    nonisolated init(_ calendarColor: CalendarColor) {
        self.init(red: calendarColor.red, green: calendarColor.green, blue: calendarColor.blue)
    }
}

/// Sync errors and permission warnings with recovery actions.
struct HomeBanners: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(\.openURL) private var openURL
    @State private var refreshStatus = UIApplication.shared.backgroundRefreshStatus

    var body: some View {
        VStack(spacing: 12) {
            if let error = coordinator.lastError {
                Banner(systemImage: "exclamationmark.triangle.fill", color: Color(.danger), text: Text(verbatim: error))
            }
            switch refreshStatus {
            case .available:
                EmptyView()
            case .denied:
                Banner(
                    systemImage: "arrow.clockwise",
                    color: Color(.warning),
                    text: Text("Background App Refresh is off, so workouts appear only when you open Gainsday."),
                    buttonTitle: "Turn On in Settings"
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            default:
                Banner(
                    systemImage: "arrow.clockwise",
                    color: Color(.warning),
                    text: Text("Background App Refresh isn't available, so workouts appear only when you open Gainsday.")
                )
            }
            if coordinator.calendarAccess == .addOnly {
                Banner(
                    systemImage: "lock.fill",
                    color: Color(.warning),
                    text: Text("With add-only access, Gainsday can't update, undo or match events."),
                    buttonTitle: "Grant Full Access"
                ) {
                    Task { await coordinator.grantFullCalendarAccess() }
                }
            }
        }
        .task {
            for await _ in NotificationCenter.default.signals(named: UIApplication.backgroundRefreshStatusDidChangeNotification) {
                refreshStatus = UIApplication.shared.backgroundRefreshStatus
            }
        }
    }
}

private struct Banner: View {
    let systemImage: String
    let color: Color
    let text: Text
    var buttonTitle: LocalizedStringKey?
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                text
                    .font(.subheadline)
                    .foregroundStyle(Color(.ink))
                if let buttonTitle {
                    Button(buttonTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 20))
    }
}

/// Daily calendar workout counts for the past week.
struct WeekStrip: View {
    let items: [FeedItem]
    let workouts: [UUID: Workout]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let synced = items.filter { $0.status.isInCalendar && $0.date >= days[0] }
        let seconds = synced.compactMap { workouts[$0.id] }.map { $0.end.timeIntervalSince($0.start) }.reduce(0, +)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 days")
                    .font(.headline)
                    .foregroundStyle(Color(.ink))
                Spacer()
                Group {
                    if seconds > 0 {
                        Text("\(synced.count) workouts · \(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))")
                    } else {
                        Text("\(synced.count) workouts")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color(.inkSecondary))
            }
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let count = synced.count { calendar.isDate($0.date, inSameDayAs: day) }
                    let isToday = calendar.isDateInToday(day)
                    VStack(spacing: 8) {
                        Text(day, format: .dateTime.weekday(.narrow))
                            .font(.caption.weight(isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? Color(.ink) : Color(.inkSecondary))
                        Text(verbatim: count > 0 ? "\(count)" : "")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(Color.onVolt)
                            .frame(width: 36, height: 36)
                            .background(count > 0 ? Color(.volt) : Color(.hairline).opacity(0.7), in: .circle)
                            .overlay {
                                if isToday { Circle().strokeBorder(Color(.ink), lineWidth: 2) }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(day.formatted(.dateTime.weekday(.wide))): \(count) workouts"))
                }
            }
        }
        .card()
    }
}

/// A held workout's matching and separate-event choices.
struct ReviewCard: View {
    @Environment(SyncCoordinator.self) private var coordinator
    let item: FeedItem
    let match: () -> Void
    @State private var addFailed = false
    @State private var notAddedReason: SkipReason?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.current.activityType?.tint ?? Color(.workoutOther))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 12) {
                Text("Needs your call")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color(.warning))
                Text("\(Text(verbatim: item.current.title).bold()), \(Text(item.date, format: .dateTime.weekday().hour().minute())). Was this a workout you planned?")
                    .font(.body)
                    .foregroundStyle(Color(.ink))
                HStack(spacing: 10) {
                    Button("Match to Plan", action: match)
                        .buttonStyle(CompactPrimaryButtonStyle())
                    Button("Keep Separate") {
                        Task { await addSeparately() }
                    }
                    .buttonStyle(.secondary)
                }
                .disabled(coordinator.isSyncing || !coordinator.hasFullCalendarAccess)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.warning).opacity(0.12), in: .rect(cornerRadius: 20))
        .alert("Couldn't Add the Event", isPresented: $addFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            if let notAddedReason {
                Text(notAddedReason.logDescription)
            } else {
                Text("The workout may have changed in Health. Try again later.")
            }
        }
    }

    private func addSeparately() async {
        do {
            try await coordinator.addSeparateEvent(for: item.current)
        } catch {
            if case ManualMatchError.notAdded(let reason) = error {
                notAddedReason = reason
            } else {
                notAddedReason = nil
            }
            addFailed = true
        }
    }
}

/// A primary capsule button sized for a card.
struct CompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .foregroundStyle(Color(.buttonLabel))
            .background(Color(.buttonFill), in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
    }
}

/// A workout summary and status in the feed.
struct FeedCard: View {
    let item: FeedItem
    let workout: Workout?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.current.activityType?.tint ?? Color(.workoutOther))
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.current.title)
                    .font(.headline)
                    .foregroundStyle(item.status.isInCalendar ? Color(.ink) : Color(.inkSecondary))
                    .lineLimit(1)
                WorkoutSummary(date: item.date, workout: workout)
                    .font(.subheadline)
                    .foregroundStyle(Color(.inkSecondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            item.status.badge
        }
        .fixedSize(horizontal: false, vertical: true)
        .card(padding: 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A workout's times and available stats.
struct WorkoutSummary: View {
    let date: Date
    let workout: Workout?

    var body: some View {
        if let workout {
            let parts = [distance(workout), heartRate(workout)].compactMap(\.self)
            Text("\(Text(workout.start..<max(workout.start, workout.end), format: .interval.hour().minute()))\(Text(verbatim: parts.map { " · " + $0 }.joined()))")
        } else {
            Text(date, format: .dateTime.hour().minute())
        }
    }

    private func distance(_ workout: Workout) -> String {
        guard let meters = workout.metrics.distanceMeters, meters > 0 else {
            return Duration.seconds(workout.end.timeIntervalSince(workout.start)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        }
        return Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    private func heartRate(_ workout: Workout) -> String? {
        workout.metrics.averageHeartRate.map { String(localized: "\(Int($0.rounded())) bpm") }
    }
}

/// A skipped-workout count beside a navigation chevron.
struct SkippedRow: View {
    let items: [FeedItem]

    var body: some View {
        HStack {
            Text("\(items.count) skipped")
                .font(.subheadline)
                .foregroundStyle(Color(.inkSecondary))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.inkTertiary))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}

/// The workouts Gainsday left out, and why.
struct SkippedView: View {
    let items: [FeedItem]

    var body: some View {
        List(items) { item in
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.current.title)
                    .font(.headline)
                Text(item.current.action.logDescription)
                    .font(.subheadline)
                    .foregroundStyle(Color(.inkSecondary))
                Text(item.date, format: .dateTime.weekday().day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(Color(.inkSecondary))
            }
            .listRowBackground(Color(.card))
        }
        .canvasBackground()
        .navigationTitle("Skipped")
    }
}
