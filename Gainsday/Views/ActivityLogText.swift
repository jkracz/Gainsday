import Foundation
import SyncCore

extension SyncAction {
    /// What the action did and why, as the activity log shows it.
    var logDescription: LocalizedStringResource {
        switch self {
        case .create: "Added to your calendar"
        case .update: "Updated because the workout changed in Health"
        case .delete: "Removed because the workout was deleted in Health"
        case .release: "Left alone from now on because you edited the event"
        case .holdForReview: "Waiting for your review"
        case .relink: "Found in your calendar and linked again, so it isn't added twice"
        case .skip(_, let reason): reason.logDescription
        }
    }
}

extension SkipReason {
    var logDescription: LocalizedStringResource {
        switch self {
        case .typeDisabled: "Skipped because this workout type is turned off"
        case .tooShort: "Skipped because it's shorter than the minimum duration"
        case .beforeSyncStartDate: "Skipped because it started before syncing was set up"
        case .tombstoned: "Won't be added again because you deleted its event"
        case .alreadySynced: "Skipped because it's already in your calendar"
        case .sourceNotAllowed: "Skipped because it was recorded by an app you didn't allow"
        case .requiresFullAccess: "Not changed because Gainsday has add-only calendar access"
        }
    }
}

extension ActivityLogEntry.Undo {
    /// The question the Undo confirmation asks.
    var confirmationTitle: LocalizedStringResource {
        switch self {
        case .removeCreatedEvent: "Remove this event?"
        case .restoreEvent: "Put the event back as it was?"
        case .recreateEvent: "Add the event back?"
        }
    }

    var confirmationMessage: LocalizedStringResource {
        switch self {
        case .removeCreatedEvent: "Gainsday deletes the event and won't add this workout again."
        case .restoreEvent: "Gainsday restores the event's earlier title, time and notes, and won't change it again."
        case .recreateEvent: "Gainsday adds the event again as it was, and won't change it again."
        }
    }

    var confirmationButton: LocalizedStringResource {
        switch self {
        case .removeCreatedEvent: "Remove Event"
        case .restoreEvent: "Restore Event"
        case .recreateEvent: "Add Event Back"
        }
    }
}
