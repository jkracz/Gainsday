import Foundation
import SwiftUI
import SyncCore

/// One workout in the home feed: the latest thing Gainsday did with it, and
/// everything before that, from the activity log.
struct FeedItem: Identifiable, Hashable {
    /// The newest entry for the workout. Its status is the card's badge.
    let latest: ActivityLogEntry
    /// Every entry for the workout, newest first, the latest included.
    let history: [ActivityLogEntry]

    var id: UUID { latest.workoutID }

    /// When the workout started, or when the entry was logged if that isn't known.
    var date: Date { latest.workoutStart ?? latest.date }

    var status: FeedStatus { FeedStatus(latest) }

    /// The log grouped by workout, newest first.
    static func items(from log: [ActivityLogEntry]) -> [FeedItem] {
        var order: [UUID] = []
        var byWorkout: [UUID: [ActivityLogEntry]] = [:]
        for entry in log.sorted(by: { $0.date > $1.date }) {
            if byWorkout[entry.workoutID] == nil { order.append(entry.workoutID) }
            byWorkout[entry.workoutID, default: []].append(entry)
        }
        return order.compactMap { id in
            guard let entries = byWorkout[id], let latest = entries.first else { return nil }
            return FeedItem(latest: latest, history: entries)
        }
        .sorted { $0.date > $1.date }
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
            self = .undone
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
