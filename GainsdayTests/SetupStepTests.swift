import Testing
@testable import Gainsday

@Suite("Setup steps")
struct SetupStepTests {
    @Test("Setup opens on the explanation, before the step that asks for Health and calendar access")
    func explanationComesFirst() {
        let steps = SetupStep.allCases

        #expect(steps.first == .welcome)
        #expect(steps.firstIndex(of: .welcome)! < steps.firstIndex(of: .connect)!)
    }

    @Test("Each step leads to the next, and Ready is the last")
    func stepsLeadToReady() {
        var visited = [SetupStep.welcome]
        while let next = visited.last?.next {
            visited.append(next)
        }

        #expect(visited == SetupStep.allCases)
        #expect(visited.last == .ready)
    }
}
