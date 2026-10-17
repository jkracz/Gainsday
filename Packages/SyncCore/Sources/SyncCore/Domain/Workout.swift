import Foundation

/// The kind of activity a workout records.
///
/// Raw values mirror `HKWorkoutActivityType`, so the HealthKit adapter maps types
/// without SyncCore importing HealthKit.
public struct WorkoutActivityType: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let cycling = WorkoutActivityType(rawValue: 13)
    public static let elliptical = WorkoutActivityType(rawValue: 16)
    public static let functionalStrengthTraining = WorkoutActivityType(rawValue: 20)
    public static let hiking = WorkoutActivityType(rawValue: 24)
    public static let rowing = WorkoutActivityType(rawValue: 35)
    public static let running = WorkoutActivityType(rawValue: 37)
    public static let swimming = WorkoutActivityType(rawValue: 46)
    public static let traditionalStrengthTraining = WorkoutActivityType(rawValue: 50)
    public static let walking = WorkoutActivityType(rawValue: 52)
    public static let yoga = WorkoutActivityType(rawValue: 57)
    public static let highIntensityIntervalTraining = WorkoutActivityType(rawValue: 63)
    public static let other = WorkoutActivityType(rawValue: 3000)
}

/// The metrics a workout may carry. Any of them can be missing, e.g. a strength
/// workout has no distance. Route and location are deliberately absent.
public struct WorkoutMetrics: Hashable, Codable, Sendable {
    public var distanceMeters: Double?
    public var activeEnergyKilocalories: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var elevationAscendedMeters: Double?

    public init(
        distanceMeters: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        elevationAscendedMeters: Double? = nil
    ) {
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.elevationAscendedMeters = elevationAscendedMeters
    }
}

/// The app that recorded a workout, e.g. the Apple Watch or Strava.
public struct WorkoutSourceApp: Hashable, Codable, Sendable {
    public var bundleIdentifier: String
    public var name: String

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// A workout from Health, identified by its UUID.
public struct Workout: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var activityType: WorkoutActivityType
    public var start: Date
    public var end: Date
    public var source: WorkoutSourceApp
    public var metrics: WorkoutMetrics

    public init(
        id: UUID = UUID(),
        activityType: WorkoutActivityType,
        start: Date,
        end: Date,
        source: WorkoutSourceApp,
        metrics: WorkoutMetrics = WorkoutMetrics()
    ) {
        self.id = id
        self.activityType = activityType
        self.start = start
        self.end = end
        self.source = source
        self.metrics = metrics
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public var interval: DateInterval { DateInterval(start: start, end: end) }

    /// The id shown in the footer and the workout section's end marker.
    public var shortID: String { id.shortID }
}

extension UUID {
    /// The first 8 hex characters, lowercased. The ledger keeps the full UUID.
    public var shortID: String {
        String(uuidString.prefix(8)).lowercased()
    }
}
