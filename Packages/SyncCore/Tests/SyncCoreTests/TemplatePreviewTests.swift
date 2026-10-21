import Foundation
import SyncCore
import Testing

@Suite("Template preview")
struct TemplatePreviewTests {
    static let now = Fixture.start

    @Test("The preview offers recent workouts newest first, then sample data for each type never recorded")
    func choices() {
        let olderRun = Fixture.workout(.running, WorkoutMetrics(distanceMeters: 3000))
        let ride = Fixture.workout(.cycling, WorkoutMetrics(distanceMeters: 20000))

        let choices = TemplatePreview.choices(recent: [ride, olderRun], now: Self.now)

        #expect(choices.prefix(2).map(\.workout) == [ride, olderRun])
        #expect(choices.prefix(2).allSatisfy { !$0.isSample })
        let samples = choices.dropFirst(2)
        #expect(samples.allSatisfy { $0.isSample })
        #expect(samples.map(\.workout.activityType) == WorkoutActivityType.known.filter { $0 != .running && $0 != .cycling })
        #expect(Set(choices.map(\.id)).count == choices.count)
    }

    @Test("With no recent workouts, the preview starts with a sample run")
    func noRecentWorkouts() throws {
        let first = try #require(TemplatePreview.choices(recent: [], now: Self.now).first)

        #expect(first.isSample)
        #expect(first.workout.activityType == .running)
        #expect(first.workout.end <= Self.now)
    }

    @Test("Sample workouts carry realistic metrics, and none for what the type doesn't measure")
    func samples() {
        let run = Workout.sample(.running, endingAt: Self.now)
        let strength = Workout.sample(.traditionalStrengthTraining, endingAt: Self.now)
        let yoga = Workout.sample(.yoga, endingAt: Self.now)

        #expect(Fixture.renderer().title("{emoji} {type} · {distance} · {pace}", for: run) == "🏃 Running · 3.23 mi · 8:40 /mi")
        #expect(strength.metrics.distanceMeters == nil)
        #expect(strength.metrics.averageHeartRate != nil)
        #expect(yoga.metrics.distanceMeters == nil)
        #expect(run.end == Self.now)
    }

    @Test("The default template leaves heart rate and calories out")
    func defaultIsPrivate() {
        let template = EventTemplate.default.title + EventTemplate.default.notes

        #expect(!template.contains("{avgHR}"))
        #expect(!template.contains("{maxHR}"))
        #expect(!template.contains("{calories}"))
    }

    @Test(
        "Every starter template renders every type without leftover placeholders or dangling separators",
        arguments: StarterTemplate.allCases
    )
    func startersRenderCleanly(_ starter: StarterTemplate) {
        for type in WorkoutActivityType.known {
            for locale in ["en_US", "de_DE"] {
                let rendered = Fixture.renderer(locale).render(starter.template, for: .sample(type, endingAt: Self.now))

                #expect(!rendered.title.isEmpty)
                #expect(!rendered.title.contains("{") && !rendered.notes.contains("{"))
                #expect(!rendered.title.hasSuffix("·") && !rendered.title.hasPrefix("·"))
                #expect(!rendered.notes.contains(": \n") && !rendered.notes.hasSuffix(":"))
            }
        }
    }

    @Test("The starters are Minimal, Detailed and Runner, and only Detailed shows heart rate")
    func starters() {
        #expect(StarterTemplate.allCases == [.minimal, .detailed, .runner])
        #expect(StarterTemplate.detailed.template.notes.contains("{avgHR}"))
        #expect(!StarterTemplate.minimal.template.notes.contains("{avgHR}"))
        #expect(!StarterTemplate.runner.template.notes.contains("{avgHR}"))
    }
}
