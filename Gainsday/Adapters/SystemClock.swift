import Foundation
import SyncCore

/// The real time, with the user's current calendar and locale.
nonisolated struct SystemClock: Clock {
    var now: Date { Date() }
    var calendar: Calendar { .autoupdatingCurrent }
    var locale: Locale { .autoupdatingCurrent }
}
