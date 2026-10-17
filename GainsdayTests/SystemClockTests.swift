import Foundation
import Testing
@testable import Gainsday

@Suite("System clock")
struct SystemClockTests {
    @Test("Reports the current time")
    func reportsCurrentTime() {
        let before = Date()
        let now = SystemClock().now
        let after = Date()

        #expect(before <= now && now <= after)
    }

    @Test("Follows the user's locale")
    func followsUserLocale() {
        #expect(SystemClock().locale.identifier == Locale.autoupdatingCurrent.identifier)
    }
}
