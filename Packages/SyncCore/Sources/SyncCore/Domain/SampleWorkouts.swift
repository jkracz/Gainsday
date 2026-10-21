import Foundation

extension Workout {
    /// A realistic workout of the given type, for previewing templates with types the
    /// user has never recorded. Metrics the type doesn't measure, such as distance on
    /// a strength workout, are left out.
    public static func sample(_ type: WorkoutActivityType, endingAt end: Date) -> Workout {
        let sample = SampleValues.of(type)
        return Workout(
            id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", type.rawValue))!,
            activityType: type,
            start: end.addingTimeInterval(-sample.minutes * 60),
            end: end,
            source: WorkoutSourceApp(bundleIdentifier: "com.apple.health", name: "Apple Watch"),
            metrics: sample.metrics
        )
    }
}

private struct SampleValues {
    var minutes: Double
    var metrics: WorkoutMetrics

    init(minutes: Double, meters: Double? = nil, kcal: Double, heartRate: (Double, Double), elevation: Double? = nil) {
        self.minutes = minutes
        metrics = WorkoutMetrics(
            distanceMeters: meters,
            activeEnergyKilocalories: kcal,
            averageHeartRate: heartRate.0,
            maxHeartRate: heartRate.1,
            elevationAscendedMeters: elevation
        )
    }

    static func of(_ type: WorkoutActivityType) -> SampleValues {
        switch type {
        case .running: SampleValues(minutes: 28, meters: 5200, kcal: 380, heartRate: (152, 171), elevation: 42)
        case .walking: SampleValues(minutes: 40, meters: 3400, kcal: 160, heartRate: (104, 121), elevation: 12)
        case .hiking: SampleValues(minutes: 130, meters: 8400, kcal: 690, heartRate: (128, 158), elevation: 420)
        case .cycling: SampleValues(minutes: 55, meters: 24000, kcal: 540, heartRate: (138, 166), elevation: 210)
        case .swimming: SampleValues(minutes: 35, meters: 1500, kcal: 330, heartRate: (135, 155))
        case .rowing: SampleValues(minutes: 25, meters: 5000, kcal: 300, heartRate: (145, 168))
        case .elliptical: SampleValues(minutes: 30, kcal: 290, heartRate: (140, 158))
        case .traditionalStrengthTraining: SampleValues(minutes: 45, kcal: 260, heartRate: (118, 151))
        case .functionalStrengthTraining: SampleValues(minutes: 40, kcal: 310, heartRate: (125, 160))
        case .highIntensityIntervalTraining: SampleValues(minutes: 25, kcal: 310, heartRate: (155, 182))
        case .yoga: SampleValues(minutes: 30, kcal: 110, heartRate: (92, 110))
        default: SampleValues(minutes: 30, kcal: 200, heartRate: (120, 140))
        }
    }
}
