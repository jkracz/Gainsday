import Foundation

/// The current time, calendar and locale, injected so tests are deterministic.
///
/// The name shadows the standard library's `Clock` inside SyncCore. Elsewhere,
/// write `SyncCore.Clock` if the compiler reports an ambiguity.
public protocol Clock: Sendable {
    var now: Date { get }
    var calendar: Calendar { get }
    var locale: Locale { get }
}
