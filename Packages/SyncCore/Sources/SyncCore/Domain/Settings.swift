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
        enabledTypes: Set<WorkoutActivityType> = Settings.defaultEnabledTypes,
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

    /// Every known type except walking, so everyday walks stay out of the calendar unless the user turns them on.
    public static let defaultEnabledTypes = Set(WorkoutActivityType.known).subtracting([.walking])

    /// A per-type override if present, otherwise the global template.
    public func template(for type: WorkoutActivityType) -> EventTemplate {
        templateOverrides[type] ?? template
    }
}

extension Settings {
    /// Reads settings saved by any version of the app. A missing or unreadable key
    /// keeps its default, so an older or newer backup still restores everything else.
    /// Add one line here for every new setting.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        container.decode(&enabledTypes, .enabledTypes)
        container.decode(&minimumDuration, .minimumDuration)
        container.decode(&sourceAllowlist, .sourceAllowlist)
        container.decode(&destinationCalendar, .destinationCalendar)
        container.decode(&template, .template)
        container.decode(&templateOverrides, .templateOverrides)
        container.decode(&footerEnabled, .footerEnabled)
        container.decode(&preferredAccessMode, .preferredAccessMode)
        container.decode(&syncStartDate, .syncStartDate)
    }
}

private extension KeyedDecodingContainer {
    /// Overwrites `value` with the stored one, if there is one this version can read.
    func decode<T: Decodable>(_ value: inout T, _ key: Key) {
        if let stored = try? decodeIfPresent(T.self, forKey: key) {
            value = stored
        }
    }
}
