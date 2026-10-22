import Foundation
import SyncCore
import Testing

@Suite("Content fingerprint")
struct ContentFingerprintTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)
    static let written = EventContent(
        title: "🏃 Running",
        start: start,
        end: start.addingTimeInterval(30 * 60),
        notes: "5.02 km · 5:58 /km\nAvg HR 152 bpm"
    )

    @Test("The fingerprint is a SHA-256 digest, so it holds none of the event's text")
    func holdsNoText() {
        let fingerprint = Self.written.fingerprint

        #expect(fingerprint.content.count == 64)
        #expect(fingerprint.content.allSatisfy { $0.isHexDigit })
        for text in ["Running", "5.02", "152", "5:58"] {
            #expect(!fingerprint.storageValue.contains(text))
        }
    }

    @Test("A calendar dropping the times' fractions of a second keeps the fingerprint")
    func dropsSubSecondPrecision() {
        var written = Self.written
        written.start = Self.start.addingTimeInterval(0.73)
        written.end = Self.start.addingTimeInterval(30 * 60 + 0.999)
        var stored = written
        stored.start = Self.start
        stored.end = Self.start.addingTimeInterval(30 * 60)

        #expect(stored.fingerprint == written.fingerprint)
    }

    @Test("Moving the event by a second changes the fingerprint")
    func secondChangesIt() {
        var moved = Self.written
        moved.start = Self.start.addingTimeInterval(1)

        #expect(moved.fingerprint != Self.written.fingerprint)
    }

    @Test("No notes and empty notes have the same fingerprint")
    func nilAndEmptyNotes() {
        var none = Self.written
        none.notes = nil
        var empty = Self.written
        empty.notes = ""

        #expect(none.fingerprint == empty.fingerprint)
    }

    @Test("Changing the title or the notes changes the fingerprint")
    func editsChangeIt() {
        var retitled = Self.written
        retitled.title = "🏃 Morning run"
        var renoted = Self.written
        renoted.notes = "5.02 km · 5:58 /km\nAvg HR 153 bpm"

        #expect(retitled.fingerprint.content != Self.written.fingerprint.content)
        #expect(renoted.fingerprint.content != Self.written.fingerprint.content)
        // Fields can't run into each other: moving text from the title to the notes counts.
        let a = EventContent(title: "ab", start: Self.start, end: Self.start, notes: "c")
        let b = EventContent(title: "a", start: Self.start, end: Self.start, notes: "bc")
        #expect(a.fingerprint.content != b.fingerprint.content)
    }

    @Test("An adopted event's times and workout section have their own fingerprint, which ignores the user's title and notes")
    func adoptedPart() {
        let workoutID = UUID()
        var plan = Self.written
        plan.title = "Tempo run"
        plan.notes = WorkoutSection.replacing(in: "Bring water", with: "5.02 km", workoutID: workoutID)
        var userEdited = plan
        userEdited.title = "Tempo run with Sam"
        userEdited.notes = WorkoutSection.replacing(in: "Bring water and gels", with: "5.02 km", workoutID: workoutID)
        var sectionEdited = plan
        sectionEdited.notes = WorkoutSection.replacing(in: "Bring water", with: "5.03 km", workoutID: workoutID)
        var moved = plan
        moved.end = plan.end.addingTimeInterval(60)
        var noSection = plan
        noSection.notes = "Bring water"

        #expect(userEdited.fingerprint.timesAndSection == plan.fingerprint.timesAndSection)
        #expect(sectionEdited.fingerprint.timesAndSection != plan.fingerprint.timesAndSection)
        #expect(moved.fingerprint.timesAndSection != plan.fingerprint.timesAndSection)
        #expect(noSection.fingerprint.timesAndSection != plan.fingerprint.timesAndSection)
    }

    @Test("The title has its own fingerprint, for finding the event by title and times")
    func titlePart() {
        var renoted = Self.written
        renoted.notes = "Other"

        #expect(renoted.fingerprint.hasTitle("🏃 Running"))
        #expect(!renoted.fingerprint.hasTitle("🏃 Morning run"))
    }

    @Test("A fingerprint survives being stored as text, and unreadable text gives none")
    func storage() {
        let fingerprint = Self.written.fingerprint

        #expect(ContentFingerprint(storageValue: fingerprint.storageValue) == fingerprint)
        #expect(ContentFingerprint(storageValue: "") == nil)
        #expect(ContentFingerprint(storageValue: "v9 abc") == nil)
    }
}
