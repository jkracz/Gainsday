import Foundation

/// The deterministic first step of matching: keyword rules over the titles of the
/// candidate planned events. [v1.1]
///
/// A keyword of the workout's type is a strong match signal, and a keyword of a
/// different type a strong non-match signal. Exactly one strong match is a match.
/// No candidates, or only strong non-matches, is no match. Anything else, such as
/// several strong matches or keyword-free titles like "Gym w/ Alex", is unclear.
struct MatchRules {
    enum Outcome: Equatable {
        case match(CalendarEvent)
        case noMatch
        /// The candidates the rules couldn't rule out.
        case unclear([CalendarEvent])
    }

    private let ownKeywords: [[String]]
    private let otherKeywords: [[String]]

    /// Rules for a workout type, with the user's keywords added to the built-in ones.
    init(for type: WorkoutActivityType, userKeywords: [WorkoutActivityType: [String]]) {
        let all = MatchKeywords.builtIn.merging(userKeywords) { $0 + $1 }
        let own = Set((all[type] ?? []).map(Self.words).filter { !$0.isEmpty })
        // A keyword shared with the workout's type, e.g. "strength" for both kinds of
        // strength training, never counts against it.
        let others = Set(all.filter { $0.key != type }.values.joined().map(Self.words).filter { !$0.isEmpty })
        ownKeywords = Array(own)
        otherKeywords = Array(others.subtracting(own))
    }

    func outcome(for candidates: [CalendarEvent]) -> Outcome {
        var strongMatches: [CalendarEvent] = []
        var notRuledOut: [CalendarEvent] = []
        for candidate in candidates {
            let title = Self.words(candidate.content.title)
            let isMatch = ownKeywords.contains { title.contains(phrase: $0) }
            let isNonMatch = otherKeywords.contains { title.contains(phrase: $0) }
            if isMatch, !isNonMatch {
                strongMatches.append(candidate)
            }
            if isMatch || !isNonMatch {
                notRuledOut.append(candidate)
            }
        }
        if strongMatches.count == 1, let match = strongMatches.first {
            return .match(match)
        }
        return notRuledOut.isEmpty ? .noMatch : .unclear(notRuledOut)
    }

    /// The text's words, lowercased and without accents or punctuation, so "Tempo-Run!"
    /// and "tempo run" read the same.
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

private extension Array where Element == String {
    /// Whether the words contain `phrase` as consecutive whole words.
    func contains(phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= count else { return false }
        return (0...(count - phrase.count)).contains { Array(self[$0..<($0 + phrase.count)]) == phrase }
    }
}
