import Foundation

/// The visible "— Logged by Gainsday · <shortId>" line at the end of an owned
/// event's notes. It tells the user where the event came from, and lets the app
/// recognise its own events after a reinstall.
public enum Footer {
    /// The footer line for a workout. Not localised, so the app can always recognise it.
    public static func line(for workoutID: UUID) -> String {
        prefix + workoutID.shortID
    }

    private static let prefix = "— Logged by Gainsday · "

    /// The notes with the footer appended after a blank line.
    public static func appending(to notes: String, workoutID: UUID) -> String {
        notes.isEmpty ? line(for: workoutID) : notes + "\n\n" + line(for: workoutID)
    }

    /// Whether the notes carry the workout's footer.
    public static func isPresent(in notes: String?, workoutID: UUID) -> Bool {
        notes?.contains(line(for: workoutID)) ?? false
    }

    /// Whether the notes carry any workout's footer.
    static func isAnyPresent(in notes: String?) -> Bool {
        notes?.contains(prefix) ?? false
    }
}
