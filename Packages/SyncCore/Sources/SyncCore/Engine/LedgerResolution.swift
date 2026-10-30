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
    ///
    /// An owned or adopted survivor created after a duplicate's release, or an owned one
    /// created after a tombstone, was made without knowing about it, e.g. by the first
    /// pass after a reinstall whose ledger arrived late. The user's decision wins (see
    /// `carryOverDecision`). A release naming another event counts too when that event
    /// has gone: a server sync can change an event's identifier, so it may well be the
    /// survivor's event under its old one.
    func resolvedEntry(forWorkout workoutID: UUID) async throws -> LedgerEntry? {
        let entries = try await ledger.entries(forWorkout: workoutID)
        guard var survivor = LedgerEntry.survivor(of: entries) else { return nil }
        var others: [LedgerEntry] = []
        for other in entries where other.id != survivor.id {
            if other.isReleasedDuplicate(of: survivor), try await isSeparateEvent(of: other) { continue }
            others.append(other)
        }
        guard !others.isEmpty else { return survivor }

        var changed = false
        if let decision = survivor.missedDecision(among: others) {
            if try await carryOverDecision(of: decision, to: &survivor) {
                changed = true
            } else {
                others.removeAll { $0.id == decision.id }
            }
        }
        let members = others.reduce(survivor.memberIDs) { $0.union($1.memberIDs) }
        if members != survivor.memberIDs {
            survivor.memberIDs = members
            changed = true
        }
        if changed {
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

    /// Applies a release or tombstone the survivor didn't know about. A release keeps
    /// the event as the user has it. A tombstone deletes the event if it's still as the
    /// app wrote it, or releases it if the user has changed it since. False, changing
    /// nothing, when add-only access can't delete the event yet: the tombstone is kept
    /// for a later pass.
    private func carryOverDecision(of decision: LedgerEntry, to survivor: inout LedgerEntry) async throws -> Bool {
        var state = decision.state
        if state == .tombstoned, let eventID = survivor.eventExternalIdentifier {
            guard await calendar.accessMode() == .full else { return false }
            if let event = try await calendar.event(withID: eventID) {
                if event.content.matches(survivor.writtenFingerprint) {
                    try await calendar.delete(eventID: eventID)
                } else {
                    state = .released
                }
            }
        }
        survivor.state = state
        survivor.updatedAt = clock.now
        return true
    }

    /// Deletes a duplicate entry's event if it's an owned event the user hasn't changed,
    /// or is already gone. False when the app can't read it, it isn't owned, or the user
    /// changed it.
    private func removeDuplicateEvent(of entry: LedgerEntry) async throws -> Bool {
        guard await calendar.accessMode() == .full,
              let eventID = entry.eventExternalIdentifier else { return false }
        guard let event = try await calendar.event(withID: eventID) else { return true }
        guard entry.state == .owned, event.content.matches(entry.writtenFingerprint) else { return false }
        try await calendar.delete(eventID: eventID)
        return true
    }

    /// Whether a released duplicate's event is the user's own copy, still in the
    /// calendar, rather than the survivor's event under an identifier it has since
    /// lost. Assumed so when the app can't read the calendar.
    private func isSeparateEvent(of entry: LedgerEntry) async throws -> Bool {
        guard await calendar.accessMode() == .full, let eventID = entry.eventExternalIdentifier else { return true }
        return try await calendar.event(withID: eventID) != nil
    }
}

private extension LedgerEntry {
    /// Whether both entries link an event, and not the same one.
    func linksOtherEvent(than survivor: LedgerEntry) -> Bool {
        guard state != .tombstoned, let eventID = eventExternalIdentifier,
              let survivorEventID = survivor.eventExternalIdentifier else { return false }
        return eventID != survivorEventID
    }

    /// The most recent release or tombstone among the duplicates that this entry was
    /// created after, so it can't have known about it. An adopted event is the user's
    /// plan, so only a release carries over to it: the app never deletes a plan.
    func missedDecision(among others: [LedgerEntry]) -> LedgerEntry? {
        let decisions: [LedgerEntry.State] = switch state {
        case .owned: [.released, .tombstoned]
        case .adopted: [.released]
        case .released, .tombstoned: []
        }
        return others
            .filter { decisions.contains($0.state) && createdAt > $0.updatedAt }
            .max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
    }

    /// A duplicate kept, released, for the user's own copy of the workout's event.
    func isReleasedDuplicate(of survivor: LedgerEntry) -> Bool {
        state == .released && linksOtherEvent(than: survivor)
    }
}
