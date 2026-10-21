import EventKit
import EventKitUI
import SwiftUI
import SyncCore

/// The system calendar chooser. It works with add-only access, where the app itself
/// can't list calendars, because iOS shows the calendars rather than the app.
struct CalendarChooser: UIViewControllerRepresentable {
    var selectedID: String?
    let onFinish: (CalendarInfo?) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = context.coordinator.store
        let chooser = EKCalendarChooser(selectionStyle: .single, displayStyle: .writableCalendarsOnly, entityType: .event, eventStore: store)
        chooser.showsDoneButton = true
        chooser.showsCancelButton = true
        chooser.delegate = context.coordinator
        if let selected = selectedID.flatMap(store.calendar(withIdentifier:)) {
            chooser.selectedCalendars = [selected]
        }
        return UINavigationController(rootViewController: chooser)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, EKCalendarChooserDelegate {
        let store = EKEventStore()
        let onFinish: (CalendarInfo?) -> Void

        init(onFinish: @escaping (CalendarInfo?) -> Void) {
            self.onFinish = onFinish
        }

        func calendarChooserDidFinish(_ chooser: EKCalendarChooser) {
            onFinish(chooser.selectedCalendars.first.map(EventKitCalendarStore.calendarInfo))
        }

        func calendarChooserDidCancel(_ chooser: EKCalendarChooser) {
            onFinish(nil)
        }
    }
}
