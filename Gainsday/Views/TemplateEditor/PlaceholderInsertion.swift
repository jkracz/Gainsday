import Foundation

/// Inserts a placeholder chip's text into a template field.
enum PlaceholderInsertion {
    /// Replaces `range` (the cursor or selection) with `token`, or appends it when
    /// there's no cursor, and returns where the cursor should go: just after it.
    static func insert(_ token: String, into text: inout String, replacing range: Range<String.Index>?) -> String.Index {
        let range = range.flatMap { $0.clamped(to: text.startIndex..<text.endIndex) } ?? text.endIndex..<text.endIndex
        let offset = text.distance(from: text.startIndex, to: range.lowerBound) + token.count
        text.replaceSubrange(range, with: token)
        return text.index(text.startIndex, offsetBy: offset)
    }
}
