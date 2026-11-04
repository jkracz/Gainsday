import Testing
@testable import Gainsday

@Suite("Setup steps")
struct SetupStepTests {
    @Test("Setup explains access before asking for permissions")
    func explanationComesFirst() {
        let steps = SetupStep.allCases

        #expect(steps.first == .welcome)
    }
}
