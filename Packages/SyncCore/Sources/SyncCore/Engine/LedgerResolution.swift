import Foundation

extension LedgerEntry {
    /// The entry to keep when iCloud merges leave several for one workout: a live
    /// entry over a tombstone, then the most recently updated, then the lowest id.
    /// Every device picks the same one.
    public static func survivor(of entries: [LedgerEntry]) -> LedgerEntry? {
        entries.min { a, b in
            let aKey = (a.state == .tombstoned ? 1 : 0, -a.updatedAt.timeIntervalSinceReferenceDate, a.id.uuidString)
            let bKey = (b.state == .tombstoned ? 1 : 0, -b.updatedAt.timeIntervalSinceReferenceDate, b.id.uuidString)
            return aKey < bKey
        }
    }
}

extension SyncEngine {
    /// The workout's single ledger entry, or nil if it has none. Duplicates are
    /// collapsed into the survivor, which keeps every cluster member they covered.
    ///
    /// A duplicate can link another event, when two devices each synced the workout
    /// before iCloud merged their ledgers. That event is deleted if it's still as the
    /// app wrote it. Otherwise it's the user's: the duplicate is kept, released, so the
    /// app leaves the event alone and never offers it as a plan.
    func resolvedEntry(forWorkout workoutID: UUID) async throws -> LedgerEntry? {
        let entries = try await ledger.entries(forWorkout: workoutID)
        guard var survivor = LedgerEntry.survivor(of: entries) else { return nil }
        let others = entries.filter { $0.id != survivor.id && !$0.isReleasedDuplicate(of: survivor) }
        guard !others.isEmpty else { return survivor }

        let members = others.reduce(survivor.memberIDs) { $0.union($1.memberIDs) }
        if members != survivor.memberIDs {
            survivor.memberIDs = members
            try await ledger.save(survivor)
        }
        for other in others {
            if other.linksOtherEvent(than: survivor), try await !removeDuplicateEvent(of: other) {
                var released = other
                // Its update time stays as it was, so it never outranks the survivor.
                released.state = .released
                try await ledger.save(released)
                continue
            }
            try await ledger.delete(entryID: other.id)
        }
        return survivor
    }

    /// Deletes a duplicate entry's event if it's an owned event the user hasn't changed,
    /// or is already gone. False when the app can't read it or the user changed it.
    private func removeDuplicateEvent(of entry: LedgerEntry) async throws -> Bool {
        guard entry.state == .owned, await calendar.accessMode() == .full,
              let eventID = entry.eventExternalIdentifier else { return false }
        guard let event = try await calendar.event(withID: eventID) else { return true }
        guard event.content.matches(entry.written) else { return false }
        try await calendar.delete(eventID: eventID)
        return true
    }
}

private extension LedgerEntry {
    /// Whether both entries link an event, and not the same one.
    func linksOtherEvent(than survivor: LedgerEntry) -> Bool {
        guard state != .tombstoned, let eventID = eventExternalIdentifier,
              let survivorEventID = survivor.eventExternalIdentifier else { return false }
        return eventID != survivorEventID
    }

    /// A duplicate kept, released, for the user's own copy of the workout's event.
    func isReleasedDuplicate(of survivor: LedgerEntry) -> Bool {
        state == .released && linksOtherEvent(than: survivor)
    }
}
