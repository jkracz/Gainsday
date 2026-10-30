import Foundation
import SyncCore

extension CalendarReference {
    /// The calendar's name as the app shows it. The default calendar, used with
    /// add-only access, has no name the app can see.
    var displayTitle: String {
        isDefaultCalendar ? String(localized: "Default Calendar") : title
    }
}
