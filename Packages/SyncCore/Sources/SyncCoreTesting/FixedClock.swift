import Foundation
import SyncCore

/// A clock stopped at a given time, with a fixed calendar and locale.
public struct FixedClock: Clock {
    public var now: Date
    public var calendar: Calendar
    public var locale: Locale

    public init(now: Date, locale: Locale = Locale(identifier: "en_US"), timeZone: TimeZone = TimeZone(identifier: "UTC")!) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }
}
