import Foundation

/// A `{name}` a template can contain. Route and location are deliberately absent.
public enum TemplatePlaceholder: String, CaseIterable, Sendable {
    case emoji
    case type
    case distance
    case duration
    case pace
    case speed
    case avgHR
    case maxHR
    case calories
    case elevation
    case start
    case end
    case date
    case source

    /// The text inserted into a template, e.g. `{pace}`.
    public var token: String { "{\(rawValue)}" }
}
