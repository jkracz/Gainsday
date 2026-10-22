import Foundation

/// Editing the user's own match keywords. [v1.1]
extension Settings {
    /// Adds a keyword for a workout type, trimmed. Returns false, and changes nothing, when
    /// it has no words or the type already has it, built in or added before, ignoring case,
    /// accents and punctuation.
    @discardableResult
    public mutating func addMatchKeyword(_ keyword: String, for type: WorkoutActivityType) -> Bool {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = MatchRules.words(trimmed)
        let existing = (MatchKeywords.builtIn[type] ?? []) + (matchKeywords[type] ?? [])
        guard !words.isEmpty, !existing.contains(where: { MatchRules.words($0) == words }) else { return false }
        matchKeywords[type, default: []].append(trimmed)
        return true
    }

    /// Removes one of the user's keywords. A type left with none is removed too.
    public mutating func removeMatchKeyword(_ keyword: String, for type: WorkoutActivityType) {
        matchKeywords[type]?.removeAll { $0 == keyword }
        if matchKeywords[type]?.isEmpty == true {
            matchKeywords[type] = nil
        }
    }
}
