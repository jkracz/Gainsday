import SyncCore
import UIKit

extension SyncCoordinator {
    var hasFullCalendarAccess: Bool { calendarAccess == .full }

    /// Upgrades add-only access to full access. iOS asks once; after that the switch
    /// is in Settings, so open it there. The next pass links the events added so far.
    func grantFullCalendarAccess() async {
        let granted = (try? await calendar.requestFullAccess()) ?? false
        guard granted else {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }
        await sync()
    }
}
