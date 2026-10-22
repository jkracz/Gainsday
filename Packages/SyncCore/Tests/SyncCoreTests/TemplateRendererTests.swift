import Foundation
import SyncCore
import Testing

@Suite("Template renderer")
struct TemplateRendererTests {
    @Test("The default title fills in the emoji, type and distance")
    func defaultTitle() {
        let rendered = Fixture.renderer().render(.default, for: Fixture.run)

        #expect(rendered.title == "🏃 Running · 3.25 mi")
    }

    struct PlaceholderCase: Sendable, CustomTestStringConvertible {
        var locale: String
        var placeholder: String
        var expected: String
        var testDescription: String { "\(placeholder) in \(locale)" }
    }

    /// The run is 5.234 km (3.25 mi) in 28:47, from 14:13:20 to 14:42:07 UTC on 21 Sep 2026.
    /// US English is imperial and 12-hour, British English is miles and 24-hour, German is metric and 24-hour.
    static let placeholderCases: [PlaceholderCase] = [
        .init(locale: "en_US", placeholder: "{emoji}", expected: "🏃"),
        .init(locale: "en_US", placeholder: "{type}", expected: "Running"),
        .init(locale: "en_US", placeholder: "{source}", expected: "Apple Watch"),
        .init(locale: "en_US", placeholder: "{duration}", expected: "29 min"),
        .init(locale: "en_US", placeholder: "{distance}", expected: "3.25 mi"),
        .init(locale: "en_GB", placeholder: "{distance}", expected: "3.25 mi"),
        .init(locale: "de_DE", placeholder: "{distance}", expected: "5,23 km"),
        .init(locale: "en_US", placeholder: "{pace}", expected: "8:51 /mi"),
        .init(locale: "en_GB", placeholder: "{pace}", expected: "8:51 /mi"),
        .init(locale: "de_DE", placeholder: "{pace}", expected: "5:30 /km"),
        .init(locale: "en_US", placeholder: "{speed}", expected: "6.8 mph"),
        .init(locale: "de_DE", placeholder: "{speed}", expected: "10,9 km/h"),
        .init(locale: "en_US", placeholder: "{avgHR}", expected: "152 bpm"),
        .init(locale: "en_US", placeholder: "{maxHR}", expected: "172 bpm"),
        .init(locale: "en_US", placeholder: "{calories}", expected: "380 Cal"),
        .init(locale: "de_DE", placeholder: "{calories}", expected: "380 kcal"),
        .init(locale: "en_US", placeholder: "{elevation}", expected: "138 ft"),
        .init(locale: "de_DE", placeholder: "{elevation}", expected: "42 m"),
        .init(locale: "en_US", placeholder: "{start}", expected: "2:13\u{202F}PM"),
        .init(locale: "en_US", placeholder: "{end}", expected: "2:42\u{202F}PM"),
        .init(locale: "en_GB", placeholder: "{start}", expected: "14:13"),
        .init(locale: "de_DE", placeholder: "{end}", expected: "14:42"),
        .init(locale: "en_US", placeholder: "{date}", expected: "Sep 21, 2026"),
        .init(locale: "de_DE", placeholder: "{date}", expected: "21. Sept. 2026"),
    ]

    @Test("Each placeholder is formatted with the region's units, number format and clock", arguments: placeholderCases)
    func placeholderValue(_ testCase: PlaceholderCase) {
        let renderer = Fixture.renderer(testCase.locale)

        #expect(renderer.notes("Value: \(testCase.placeholder)", for: Fixture.run) == "Value: \(testCase.expected)")
    }

    struct MissingValueCase: Sendable, CustomTestStringConvertible {
        var workout: Workout
        var title: String
        var notes: String
        var testDescription: String { workout.activityType.name }
    }

    /// Workouts that lack distance, heart rate or both, rendered with a template that uses everything.
    static let missingValueCases: [MissingValueCase] = [
        .init(
            workout: Fixture.workout(.traditionalStrengthTraining, WorkoutMetrics(activeEnergyKilocalories: 260, averageHeartRate: 118, maxHeartRate: 151)),
            title: "🏋️ Strength Training · 45 min",
            notes: "Duration: 45 min\nHeart rate: 118 bpm (max 151 bpm)\nEnergy: 260 Cal"
        ),
        .init(
            workout: Fixture.workout(.yoga, WorkoutMetrics()),
            title: "🧘 Yoga · 45 min",
            notes: "Duration: 45 min"
        ),
        .init(
            workout: Fixture.workout(.highIntensityIntervalTraining, WorkoutMetrics(activeEnergyKilocalories: 310)),
            title: "💪 HIIT · 45 min",
            notes: "Duration: 45 min\nEnergy: 310 Cal"
        ),
        .init(
            workout: Fixture.workout(.functionalStrengthTraining, WorkoutMetrics(averageHeartRate: 125)),
            title: "🏋️ Functional Strength Training · 45 min",
            notes: "Duration: 45 min"
        ),
        .init(
            workout: Fixture.workout(.elliptical, WorkoutMetrics(averageHeartRate: 140, maxHeartRate: 160)),
            title: "💪 Elliptical · 45 min",
            notes: "Duration: 45 min\nHeart rate: 140 bpm (max 160 bpm)"
        ),
        .init(
            workout: Fixture.workout(.walking, WorkoutMetrics(distanceMeters: 4023.36)),
            title: "🚶 Walking · 2.5 mi · 45 min",
            notes: "Duration: 45 min\nDistance: 2.5 mi\nPace: 18:00 /mi"
        ),
        .init(
            workout: Fixture.workout(.other, WorkoutMetrics(distanceMeters: 0)),
            title: "💪 Workout · 45 min",
            notes: "Duration: 45 min"
        ),
    ]

    @Test("Missing values drop their notes line and title segment", arguments: missingValueCases)
    func missingValues(_ testCase: MissingValueCase) {
        let template = EventTemplate(
            title: "{emoji} {type} · {distance} · {duration}",
            notes: """
            Duration: {duration}
            Distance: {distance}
            Pace: {pace}
            Heart rate: {avgHR} (max {maxHR})
            Energy: {calories}
            """
        )

        let rendered = Fixture.renderer().render(template, for: testCase.workout)

        #expect(rendered.title == testCase.title)
        #expect(rendered.notes == testCase.notes)
    }

    @Test("Unknown placeholders render literally and never drop a line or segment")
    func unknownPlaceholders() {
        let template = EventTemplate(title: "{type} · {distnace}", notes: "Route: {route}\nWhere: {location}\n{nope")

        let rendered = Fixture.renderer().render(template, for: Fixture.run)

        #expect(rendered.title == "Running · {distnace}")
        #expect(rendered.notes == "Route: {route}\nWhere: {location}\n{nope")
    }

    @Test("Blank lines inside the notes are kept, but none are left at the start or end")
    func blankLines() {
        let template = EventTemplate(title: "{type}", notes: "Distance: {distance}\n\nDuration: {duration}\n\nPace: {pace}")
        let strength = Fixture.workout(.traditionalStrengthTraining, WorkoutMetrics())

        #expect(Fixture.renderer().render(template, for: Fixture.run).notes == "Distance: 3.25 mi\n\nDuration: 29 min\n\nPace: 8:51 /mi")
        #expect(Fixture.renderer().render(template, for: strength).notes == "Duration: 45 min")
    }

    @Test("A title with every segment empty falls back to the emoji and type")
    func emptyTitle() {
        let strength = Fixture.workout(.traditionalStrengthTraining, WorkoutMetrics())

        #expect(Fixture.renderer().title("{distance} · {pace}", for: strength) == "🏋️ Strength Training")
        #expect(Fixture.renderer().title("", for: strength) == "🏋️ Strength Training")
    }

    @Test("Times and dates use the calendar's time zone")
    func timeZone() {
        let renderer = Fixture.renderer("en_GB", timeZone: "America/New_York")

        #expect(renderer.title("{date} {start}–{end}", for: Fixture.run) == "21 Sep 2026 10:13–10:42")
    }
}

/// Workouts and renderers with known values, so expected output can be written out by hand.
enum Fixture {
    /// 21 Sep 2026, 14:13 UTC.
    static let start = Date(timeIntervalSince1970: 1_790_000_000)
    static let watch = WorkoutSourceApp(bundleIdentifier: "com.apple.health", name: "Apple Watch")

    /// 5.234 km in 28 min 47 s (5:30 per km), with heart rate, energy and elevation.
    static let run = Workout(
        id: UUID(uuidString: "A1B2C3D4-E5F6-4789-8ABC-DEF012345678")!,
        activityType: .running,
        start: start,
        end: start.addingTimeInterval(1727),
        source: watch,
        metrics: WorkoutMetrics(
            distanceMeters: 5234,
            activeEnergyKilocalories: 380.4,
            averageHeartRate: 151.6,
            maxHeartRate: 172,
            elevationAscendedMeters: 42
        )
    )

    /// A 45-minute workout of the given type.
    static func workout(_ type: WorkoutActivityType, _ metrics: WorkoutMetrics) -> Workout {
        Workout(activityType: type, start: start, end: start.addingTimeInterval(45 * 60), source: watch, metrics: metrics)
    }

    static func renderer(_ localeID: String = "en_US", timeZone: String = "UTC") -> TemplateRenderer {
        let locale = Locale(identifier: localeID)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return TemplateRenderer(locale: locale, calendar: calendar)
    }
}
