import SwiftUI
import SyncCore

/// Shows features that need full calendar access. With add-only access they stay
/// visible but greyed out, followed by a notice with a button to grant full access.
///
///     RequiresFullAccess {
///         Button("Undo") { ... }
///     }
struct RequiresFullAccess<Content: View>: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @ViewBuilder let content: Content

    var body: some View {
        if coordinator.hasFullCalendarAccess {
            content
        } else {
            content
                .disabled(true)
                .foregroundStyle(.secondary)
            FullAccessNotice()
        }
    }
}

/// "Requires full calendar access", with a button to grant it.
struct FullAccessNotice: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Requires full calendar access", systemImage: "lock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Grant Full Access") {
                Task { await coordinator.grantFullCalendarAccess() }
            }
        }
    }
}
