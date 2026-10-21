import Testing
@testable import Gainsday

@Suite("Setup steps")
struct SetupStepTests {
    @Test("Setup opens on the explanation, before the steps that ask for Health and calendar access")
    func explanationComesFirst() {
        let steps = SetupStep.allCases

        #expect(steps.first == .welcome)
        #expect(steps.firstIndex(of: .welcome)! < steps.firstIndex(of: .health)!)
        #expect(steps.firstIndex(of: .welcome)! < steps.firstIndex(of: .calendar)!)
    }

    @Test("Each step leads to the next, and Start is the last")
    func stepsLeadToStart() {
        var visited = [SetupStep.welcome]
        while let next = visited.last?.next {
            visited.append(next)
        }

        #expect(visited == SetupStep.allCases)
        #expect(visited.last == .start)
    }
}
