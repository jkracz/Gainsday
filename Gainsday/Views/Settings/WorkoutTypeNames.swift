import Foundation
import SyncCore

extension WorkoutActivityType {
    /// The type's name as shown in settings.
    var displayName: String {
        switch self {
        case .cycling: String(localized: "Cycling")
        case .elliptical: String(localized: "Elliptical")
        case .functionalStrengthTraining: String(localized: "Functional Strength Training")
        case .hiking: String(localized: "Hiking")
        case .rowing: String(localized: "Rowing")
        case .running: String(localized: "Running")
        case .swimming: String(localized: "Swimming")
        case .traditionalStrengthTraining: String(localized: "Strength Training")
        case .walking: String(localized: "Walking")
        case .yoga: String(localized: "Yoga")
        case .highIntensityIntervalTraining: String(localized: "HIIT")
        default: String(localized: "Other")
        }
    }
}
