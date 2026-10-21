import Foundation

/// Add-only setup saves `CalendarReference.defaultCalendar` as the destination, since
/// iOS doesn't let the app choose a calendar with that access.
extension SyncEngine {
    /// Once the app has full access, swaps the default calendar for the calendar it is,
    /// so the destination stays put if the user changes their default later. Events
    /// added in add-only mode are found there when they're linked. Without full access,
    /// or with no default calendar, the settings are returned unchanged.
    func resolvingDefaultCalendar(in settings: Settings) async throws -> Settings {
        guard settings.destinationCalendar?.isDefaultCalendar == true,
              await calendar.accessMode() == .full,
              let id = await calendar.defaultCalendarID(),
              let resolved = try await calendar.writableCalendars().first(where: { $0.id == id }) else {
            return settings
        }
        let reference = CalendarReference(id: resolved.id, title: resolved.title)
        return await self.settings.edit { settings in
            if settings.destinationCalendar?.isDefaultCalendar == true {
                settings.destinationCalendar = reference
            }
        }
    }
}
