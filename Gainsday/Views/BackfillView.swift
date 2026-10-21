import SwiftUI
import SyncCore

/// Adds past workouts in a chosen range, after showing how many events that creates.
struct BackfillView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var from = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var to = Date.now
    @State private var preview: SyncCoordinator.BackfillPreview?
    @State private var addedCount: Int?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("To", selection: $to, in: from...Date.now, displayedComponents: .date)
            } footer: {
                if #available(iOS 27, *) {
                    Text("If you let Gainsday read only the past 30 days of Health data, older workouts can't be added.")
                }
            }

            Section {
                if let preview {
                    Text("This will create \(preview.newEventCount) events.")
                    Button("Add \(preview.newEventCount) Events") {
                        Task { await commit(preview) }
                    }
                    .disabled(preview.newEventCount == 0 || isWorking)
                } else {
                    Button("Preview") {
                        Task { await makePreview() }
                    }
                    .disabled(isWorking)
                }
            } footer: {
                if let addedCount {
                    Text("Added \(addedCount) events.")
                } else {
                    Text("Workouts already in your calendar, and those your filters leave out, aren't added again.")
                }
            }

            if let errorMessage {
                Section {
                    Text(verbatim: errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Past Workouts")
        .onChange(of: from) { preview = nil }
        .onChange(of: to) { preview = nil }
    }

    /// From the start of the first day to the end of the last, or now if that's sooner.
    private var interval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let endOfLastDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)) ?? to
        return DateInterval(start: start, end: max(start, min(endOfLastDay, .now)))
    }

    private func makePreview() async {
        isWorking = true
        defer { isWorking = false }
        do {
            preview = try await coordinator.previewBackfill(interval)
            addedCount = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commit(_ preview: SyncCoordinator.BackfillPreview) async {
        isWorking = true
        defer { isWorking = false }
        do {
            addedCount = try await coordinator.backfill(preview.interval)
            self.preview = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
