import Foundation
import Testing
@testable import Gainsday

@Suite("Placeholder insertion")
struct PlaceholderInsertionTests {
    @Test("A placeholder goes in at the cursor, and the cursor moves to just after it")
    func insertsAtCursor() {
        var text = "Run · "
        let cursor = text.index(text.startIndex, offsetBy: 3)

        let caret = PlaceholderInsertion.insert("{pace}", into: &text, replacing: cursor..<cursor)

        #expect(text == "Run{pace} · ")
        #expect(text[..<caret] == "Run{pace}")
    }

    @Test("A placeholder replaces selected text")
    func replacesSelection() {
        var text = "Distance: km"
        let selection = text.range(of: "km")!

        let caret = PlaceholderInsertion.insert("{distance}", into: &text, replacing: selection)

        #expect(text == "Distance: {distance}")
        #expect(caret == text.endIndex)
    }

    @Test("With no cursor, a placeholder is added at the end")
    func appendsWithoutCursor() {
        var text = "🏃"

        let caret = PlaceholderInsertion.insert("{type}", into: &text, replacing: nil)

        #expect(text == "🏃{type}")
        #expect(caret == text.endIndex)
    }
}
