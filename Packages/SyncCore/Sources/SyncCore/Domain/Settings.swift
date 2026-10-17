import Foundation

/// A title and notes template pair.
public struct EventTemplate: Hashable, Codable, Sendable {
    public var title: String
    public var notes: String

    public init(title: String, notes: String) {
        self.title = title
        self.notes = notes
    }

    public static let `default` = EventTemplate(
        title: "{emoji} {type} · {distance}",
        notes: """
        Duration: {duration}
        Distance: {distance}
        Pace: {pace}
        """
    )
}

/// The user's settings, backed up to iCloud key-value storage.
public struct Settings: Hashable, Codable, Sendable {
    public var enabledTypes: Set<WorkoutActivityType>
    public var minimumDuration: TimeInterval
    /// When set, only workouts from these source bundle identifiers are considered.
    public var sourceAllowlist: Set<String>?
    public var destinationCalendar: CalendarReference?
    public var template: EventTemplate
    /// Per-type overrides. Empty in v1, which has no editor for them.
    public var templateOverrides: [WorkoutActivityType: EventTemplate]
    public var footerEnabled: Bool
    public var preferredAccessMode: AccessMode
    /// The earliest workout start eligible for syncing. Nil until setup finishes.
    public var syncStartDate: Date?

    public init(
        enabledTypes: Set<WorkoutActivityType> = [],
        minimumDuration: TimeInterval = 10 * 60,
        sourceAllowlist: Set<String>? = nil,
        destinationCalendar: CalendarReference? = nil,
        template: EventTemplate = .default,
        templateOverrides: [WorkoutActivityType: EventTemplate] = [:],
        footerEnabled: Bool = true,
        preferredAccessMode: AccessMode = .full,
        syncStartDate: Date? = nil
    ) {
        self.enabledTypes = enabledTypes
        self.minimumDuration = minimumDuration
        self.sourceAllowlist = sourceAllowlist
        self.destinationCalendar = destinationCalendar
        self.template = template
        self.templateOverrides = templateOverrides
        self.footerEnabled = footerEnabled
        self.preferredAccessMode = preferredAccessMode
        self.syncStartDate = syncStartDate
    }

    /// A per-type override if present, otherwise the global template.
    public func template(for type: WorkoutActivityType) -> EventTemplate {
        templateOverrides[type] ?? template
    }
}
