import SwiftUI
import UIKit

/// Says when finished workouts appear. Syncing in the background needs Background
/// App Refresh, so when it's off this explains that and links to Settings.
struct SyncTimingFooter: View {
    @Environment(\.openURL) private var openURL
    @State private var status = UIApplication.shared.backgroundRefreshStatus

    var body: some View {
        Group {
            switch status {
            case .available:
                Text("Workouts you finish appear in this calendar shortly afterwards.")
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Background App Refresh is off for Gainsday, so workouts appear only when you open it.")
                    Button("Turn On in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
            default:
                Text("Background App Refresh isn't available on this iPhone, so workouts appear only when you open Gainsday.")
            }
        }
        .task {
            for await _ in NotificationCenter.default.signals(named: UIApplication.backgroundRefreshStatusDidChangeNotification) {
                status = UIApplication.shared.backgroundRefreshStatus
            }
        }
    }
}

