import Foundation

/// The marked block the app adds to an adopted event's notes, between a start marker
/// line and an end marker line. The end marker always carries the workout's short id,
/// even when the footer is off, so the app can find its section again. [v1.1]
///
/// The markers aren't localised, so the app can always recognise them.
public enum WorkoutSection {
    public static let startMarker = "— Workout logged by Gainsday —"

    public static func endMarker(for workoutID: UUID) -> String {
        "— End of Gainsday workout · \(workoutID.shortID) —"
    }

    /// The section for a workout: its body between the two markers.
    public static func section(_ body: String, workoutID: UUID) -> String {
        [startMarker, body, endMarker(for: workoutID)].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The notes with the workout's section replaced by `body`, or added after a blank
    /// line when it isn't there. Everything else in the notes stays as it is.
    public static func replacing(in notes: String?, with body: String, workoutID: UUID) -> String {
        let section = section(body, workoutID: workoutID)
        var lines = (notes ?? "").components(separatedBy: "\n")
        if let range = range(in: lines, workoutID: workoutID) {
            lines.replaceSubrange(range, with: [section])
            return lines.joined(separator: "\n")
        }
        let rest = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? section : (notes ?? "") + "\n\n" + section
    }

    /// The notes without the workout's section, and without the blank line before it.
    public static func removing(from notes: String?, workoutID: UUID) -> String? {
        guard let notes else { return nil }
        var lines = notes.components(separatedBy: "\n")
        guard var range = range(in: lines, workoutID: workoutID) else { return notes }
        if range.lowerBound > 0, lines[range.lowerBound - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            range = (range.lowerBound - 1)..<range.upperBound
        }
        lines.removeSubrange(range)
        return lines.joined(separator: "\n")
    }

    /// Whether the notes carry the workout's section.
    public static func isPresent(in notes: String?, workoutID: UUID) -> Bool {
        notes?.contains(endMarker(for: workoutID)) ?? false
    }

    /// Whether the notes carry any workout's section.
    static func isAnyPresent(in notes: String?) -> Bool {
        notes?.contains(startMarker) ?? false
    }

    /// The lines from the start marker to the workout's end marker.
    private static func range(in lines: [String], workoutID: UUID) -> Range<Int>? {
        guard let end = lines.firstIndex(of: endMarker(for: workoutID)) else { return nil }
        let start = lines[..<end].lastIndex(of: startMarker) ?? end
        return start..<(end + 1)
    }
}
