import Foundation
import SwiftUI
import SyncCore

/// One workout in the home feed: where it stands, and everything Gainsday did with
/// it, from the activity log.
struct FeedItem: Identifiable, Hashable {
    /// The entry that says where the workout stands, and whose actions the sheet offers:
    /// the newest, unless it undid a review choice or a manual match, which reopens the
    /// held workout or the create before it.
    let current: ActivityLogEntry
    /// Every entry for the workout, newest first.
    let history: [ActivityLogEntry]

    var id: UUID { current.workoutID }

    /// When the workout started, or when the entry was logged if that isn't known.
    var date: Date { current.workoutStart ?? current.date }

    var status: FeedStatus { FeedStatus(current) }

    /// The log grouped by workout, newest first.
    static func items(from log: [ActivityLogEntry]) -> [FeedItem] {
        var order: [UUID] = []
        var byWorkout: [UUID: [ActivityLogEntry]] = [:]
        for entry in log.sorted(by: { $0.date > $1.date }) {
            if byWorkout[entry.workoutID] == nil { order.append(entry.workoutID) }
            byWorkout[entry.workoutID, default: []].append(entry)
        }
        return order.compactMap { id in
            guard let entries = byWorkout[id], let newest = entries.first else { return nil }
            let current = newest.reopensEarlierEntry ? entries.first { $0.undoneAt == nil } ?? newest : newest
            return FeedItem(current: current, history: entries)
        }
        .sorted { $0.date > $1.date }
    }
}

private extension ActivityLogEntry {
    /// Whether undoing this entry handed the workout back to an earlier one.
    var reopensEarlierEntry: Bool {
        guard undoneAt != nil else { return false }
        switch undo {
        case .returnToReview, .separateFromPlannedEvent: return true
        default: return false
        }
    }
}

/// What a workout's card says happened to it.
enum FeedStatus: Hashable {
    case added
    case matched
    case updated
    case removed
    case yours
    case needsReview
    case skipped
    case undone

    init(_ entry: ActivityLogEntry) {
        if entry.undoneAt != nil {
            // Undoing an add removes the event, which is what the user will look for.
            if case .create = entry.action { self = .removed } else { self = .undone }
            return
        }
        switch entry.action {
        case .create: self = .added
        case .adopt: self = .matched
        case .update, .relink, .removeWorkoutSection: self = .updated
        case .delete: self = .removed
        case .release: self = .yours
        case .holdForReview: self = entry.isAwaitingReview ? .needsReview : .added
        case .skip: self = .skipped
        }
    }

    /// Whether the workout is in the user's calendar, as a new event or a planned one.
    var isInCalendar: Bool {
        switch self {
        case .added, .matched, .updated, .yours: true
        case .removed, .needsReview, .skipped, .undone: false
        }
    }

    var label: Text {
        switch self {
        case .added: Text("Added")
        case .matched: Text("Matched plan")
        case .updated: Text("Updated")
        case .removed: Text("Removed")
        case .yours: Text("Yours now")
        case .needsReview: Text("Needs review")
        case .skipped: Text("Skipped")
        case .undone: Text("Undone")
        }
    }

    var color: Color {
        switch self {
        case .added: Color(.positive)
        case .matched: Color.accentColor
        case .updated: Color(.info)
        case .needsReview: Color(.warning)
        case .removed, .yours, .skipped, .undone: Color(.inkSecondary)
        }
    }

    var badge: Badge { Badge(label, color: color) }
}
