import SyncCore

/// An anchor held in memory.
public actor InMemoryAnchorStore: WorkoutAnchorStore {
    public private(set) var anchor: WorkoutAnchor?

    public init(_ anchor: WorkoutAnchor? = nil) {
        self.anchor = anchor
    }

    public func load() async -> WorkoutAnchor? {
        anchor
    }

    public func save(_ anchor: WorkoutAnchor) async {
        self.anchor = anchor
    }
}
