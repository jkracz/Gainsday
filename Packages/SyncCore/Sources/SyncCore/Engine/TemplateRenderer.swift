import Foundation

/// A rendered title and notes, before the footer is added.
public struct RenderedTemplate: Hashable, Sendable {
    public var title: String
    public var notes: String

    public init(title: String, notes: String) {
        self.title = title
        self.notes = notes
    }
}

/// Fills a template's `{placeholders}` with a workout's values, formatted for a
/// locale and calendar. Rendering is pure and deterministic.
public struct TemplateRenderer: Sendable {
    public var locale: Locale
    public var calendar: Calendar

    public init(locale: Locale, calendar: Calendar) {
        self.locale = locale
        self.calendar = calendar
    }

    public func render(_ template: EventTemplate, for workout: Workout) -> RenderedTemplate {
        RenderedTemplate(title: title(template.title, for: workout), notes: notes(template.notes, for: workout))
    }

    /// Renders a title. Segments separated by " · " are dropped when any of their
    /// placeholders has no value, so a title never ends in a dangling separator.
    /// A title left empty falls back to the emoji and type.
    public func title(_ template: String, for workout: Workout) -> String {
        let values = PlaceholderValues(workout: workout, locale: locale, calendar: calendar)
        let title = template.components(separatedBy: Self.titleSeparator)
            .compactMap { values.substitute(in: $0) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: Self.titleSeparator)
        return title.isEmpty ? values.substitute(in: "{emoji} {type}") ?? "" : title
    }

    /// Renders notes. A line is dropped when any of its placeholders has no value,
    /// so a strength workout never shows "Distance: ".
    public func notes(_ template: String, for workout: Workout) -> String {
        let values = PlaceholderValues(workout: workout, locale: locale, calendar: calendar)
        return template.components(separatedBy: "\n")
            .compactMap { values.substitute(in: $0) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let titleSeparator = " · "
}

/// The formatted value of each placeholder for one workout. Nil means the workout
/// has no value for it, e.g. no distance on a strength workout. Route and location
/// are never available.
private struct PlaceholderValues {
    var workout: Workout
    var locale: Locale
    var calendar: Calendar

    /// The text with each known placeholder filled in, or nil if any of them has no
    /// value. Unknown placeholders are left as they are, so typos show in the preview.
    func substitute(in text: String) -> String? {
        var output = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            output += rest[..<open]
            let name = String(rest[rest.index(after: open)..<close])
            if let placeholder = TemplatePlaceholder(rawValue: name) {
                guard let value = value(for: placeholder) else { return nil }
                output += value
            } else {
                output += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return output + rest
    }

    private func value(for placeholder: TemplatePlaceholder) -> String? {
        let metrics = workout.metrics
        return switch placeholder {
        case .emoji: workout.activityType.emoji
        case .type: workout.activityType.name
        case .source: workout.source.name
        case .date: workout.start.formatted(dateStyle(date: .abbreviated, time: .omitted))
        case .start: workout.start.formatted(dateStyle(date: .omitted, time: .shortened))
        case .end: workout.end.formatted(dateStyle(date: .omitted, time: .shortened))
        case .duration: duration(workout.duration)
        case .distance: distanceMeters.map(distance)
        case .pace: distanceMeters.map(pace)
        case .speed: distanceMeters.map(speed)
        case .avgHR: metrics.averageHeartRate.map(heartRate)
        case .maxHR: metrics.maxHeartRate.map(heartRate)
        case .calories: metrics.activeEnergyKilocalories.map(energy)
        case .elevation: metrics.elevationAscendedMeters.map(elevation)
        }
    }

    /// Zero counts as missing, so a pace is never divided by nothing.
    private var distanceMeters: Double? {
        workout.metrics.distanceMeters.flatMap { $0 > 0 ? $0 : nil }
    }

    private var usesMiles: Bool {
        locale.measurementSystem != .metric
    }

    private func dateStyle(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> Date.FormatStyle {
        Date.FormatStyle(date: date, time: time, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = (seconds / 60).rounded()
        return Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale)
        )
    }

    private func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(
            .measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...2)))
                .locale(locale)
        )
    }

    /// Time per kilometre or mile, e.g. "5:30 /km".
    private func pace(_ meters: Double) -> String {
        let unit: UnitLength = usesMiles ? .miles : .kilometers
        let units = Measurement(value: meters, unit: UnitLength.meters).converted(to: unit).value
        let seconds = Duration.seconds((workout.duration / units).rounded())
        let pattern: Duration.TimeFormatStyle.Pattern = seconds < .seconds(3600) ? .minuteSecond : .hourMinuteSecond
        return "\(seconds.formatted(.time(pattern: pattern).locale(locale))) /\(unit.symbol)"
    }

    private func speed(_ meters: Double) -> String {
        let metersPerSecond = workout.duration > 0 ? meters / workout.duration : 0
        let unit: UnitSpeed = usesMiles ? .milesPerHour : .kilometersPerHour
        return Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond).converted(to: unit).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
                .locale(locale)
        )
    }

    private func heartRate(_ beatsPerMinute: Double) -> String {
        "\(Int(beatsPerMinute.rounded()).formatted(.number.locale(locale))) bpm"
    }

    private func energy(_ kilocalories: Double) -> String {
        Measurement(value: kilocalories, unit: UnitEnergy.kilocalories).formatted(
            .measurement(width: .abbreviated, usage: .workout, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }

    private func elevation(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(
            .measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }
}
