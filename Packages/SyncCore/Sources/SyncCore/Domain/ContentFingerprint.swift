import CryptoKit
import Foundation

/// An irreversible digest of what the app wrote to an event, so the ledger can spot
/// user edits without keeping the event's text. The ledger syncs to iCloud, and the
/// text holds Health data such as distance, pace and heart rate, which App Review
/// guideline 5.1.3(ii) keeps out of iCloud.
///
/// Each part is a SHA-256 hex digest of one of the comparisons the engine makes:
/// the whole event, an adopted event's times and workout section, and the title.
/// Times count to the whole second, since calendar stores may drop fractions of a
/// second, and nil and empty notes are the same.
public struct ContentFingerprint: Hashable, Codable, Sendable {
    /// The title, times and notes: an owned event is as the app wrote it.
    public var content: String
    /// The times and the workout section: an adopted event is as the app wrote it.
    public var timesAndSection: String
    /// The title alone, for finding the event again by its title and times.
    public var title: String

    public init(_ event: EventContent) {
        content = Self.digest("content", [.text(event.title), .time(event.start), .time(event.end), .text(event.notes ?? "")])
        timesAndSection = Self.digest("adopted", [.time(event.start), .time(event.end), .optionalText(WorkoutSection.text(in: event.notes))])
        title = Self.digest("title", [.text(event.title)])
    }

    /// Whether the fingerprinted event had this title.
    public func hasTitle(_ title: String) -> Bool {
        Self.digest("title", [.text(title)]) == self.title
    }

    /// The fingerprint as one line of text, for storage.
    public var storageValue: String {
        [Self.version, content, timesAndSection, title].joined(separator: " ")
    }

    /// A stored fingerprint, or nil if the text isn't one this version wrote.
    public init?(storageValue: String) {
        let parts = storageValue.split(separator: " ").map(String.init)
        guard parts.count == 4, parts[0] == Self.version,
              parts.dropFirst().allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        (content, timesAndSection, title) = (parts[1], parts[2], parts[3])
    }

    private static let version = "v1"

    private enum Field {
        case text(String)
        case optionalText(String?)
        case time(Date)
    }

    /// Hashes a hand-written encoding, so it never changes with a library's output.
    /// Each field is length-prefixed, so text can't move from one field to the next
    /// unnoticed. Text is normalised, as Swift compares strings by canonical equivalence.
    private static func digest(_ kind: String, _ fields: [Field]) -> String {
        var encoded = "gainsday.\(kind).\(version)"
        for field in fields {
            switch field {
            case .text(let text), .optionalText(let text?):
                let normalised = text.precomposedStringWithCanonicalMapping
                encoded += "|s\(normalised.utf8.count):\(normalised)"
            case .optionalText(nil):
                encoded += "|n"
            case .time(let date):
                // Rounded down, as a calendar dropping the fraction would.
                encoded += "|t\(Int64(date.timeIntervalSince1970.rounded(.down)))"
            }
        }
        return SHA256.hash(data: Data(encoded.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension EventContent {
    /// What the ledger keeps of this content to spot later edits.
    public var fingerprint: ContentFingerprint {
        ContentFingerprint(self)
    }
}
