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

    /// With add-only access iOS adds events only to the user's default calendar, and the
    /// app can't look up any other calendar, so after switching from full access the
    /// destination would look deleted. It becomes the default calendar instead, as
    /// add-only setup saves it, and upgrading again names the calendar it is. Returns
    /// the settings, changed or not.
    public func usingDefaultCalendarWithAddOnlyAccess() async -> Settings {
        let current = await settings.load()
        guard await calendar.accessMode() == .addOnly,
              current.destinationCalendar?.isDefaultCalendar == false else {
            return current
        }
        return await settings.edit { settings in
            if settings.destinationCalendar?.isDefaultCalendar == false {
                settings.destinationCalendar = .defaultCalendar
            }
        }
    }
}
