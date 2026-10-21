import Foundation
import SyncCore
import Testing

@Suite("Workout section")
struct WorkoutSectionTests {
    static let workoutID = UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000000")!

    @Test("The section goes after the user's notes, between markers that carry the short id")
    func sectionIsAppended() {
        let notes = WorkoutSection.replacing(in: "Bring gels", with: "Duration: 55 min", workoutID: Self.workoutID)

        #expect(notes == """
        Bring gels

        — Workout logged by Gainsday —
        Duration: 55 min
        — End of Gainsday workout · a1b2c3d4 —
        """)
    }

    @Test("Writing the section again replaces it and keeps everything around it")
    func sectionIsReplaced() {
        let first = WorkoutSection.replacing(in: "Bring gels", with: "Duration: 55 min", workoutID: Self.workoutID)
        let edited = first + "\nAdded later by me"

        let second = WorkoutSection.replacing(in: edited, with: "Duration: 60 min", workoutID: Self.workoutID)

        #expect(second == """
        Bring gels

        — Workout logged by Gainsday —
        Duration: 60 min
        — End of Gainsday workout · a1b2c3d4 —
        Added later by me
        """)
    }

    @Test("An event with no notes gets just the section")
    func emptyNotes() {
        #expect(WorkoutSection.replacing(in: nil, with: "Duration: 55 min", workoutID: Self.workoutID) == """
        — Workout logged by Gainsday —
        Duration: 55 min
        — End of Gainsday workout · a1b2c3d4 —
        """)
    }

    @Test("Removing the section gives back the user's notes")
    func sectionIsRemoved() {
        let notes = WorkoutSection.replacing(in: "Bring gels", with: "Duration: 55 min", workoutID: Self.workoutID)

        #expect(WorkoutSection.removing(from: notes, workoutID: Self.workoutID) == "Bring gels")
        #expect(WorkoutSection.removing(from: "Bring gels", workoutID: Self.workoutID) == "Bring gels")
        #expect(WorkoutSection.isPresent(in: notes, workoutID: Self.workoutID))
        #expect(!WorkoutSection.isPresent(in: notes, workoutID: UUID()))
    }
}
