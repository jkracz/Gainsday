import Foundation
import Testing
@testable import Gainsday

@Suite("Notification signals")
struct NotificationSignalsTests {
    let center = NotificationCenter()
    let name = Notification.Name("NotificationSignalsTests")

    @Test("Each post of the named notification yields one signal")
    func yieldsOnPost() async {
        let stream = center.signals(named: name)

        center.post(name: Notification.Name("Other"), object: nil)
        center.post(name: name, object: nil)
        center.post(name: name, object: nil)

        let count = await Task {
            var count = 0
            for await _ in stream {
                count += 1
                if count == 2 { break }
            }
            return count
        }.value
        #expect(count == 2)
    }

    @Test("A cancelled listener stops, and later posts are harmless")
    func stopsWhenCancelled() async {
        let stream = center.signals(named: name)
        let listener = Task { for await _ in stream {} }

        listener.cancel()
        await listener.value
        center.post(name: name, object: nil)
    }
}
