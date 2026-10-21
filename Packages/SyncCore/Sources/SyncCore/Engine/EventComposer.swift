import Foundation

/// Builds the title and notes of an owned event: the user's template for the
/// workout's type, rendered for the clock's locale, then the footer when it's on.
/// This is the one place the engine gets event content from.
struct EventComposer {
    var settings: Settings
    var renderer: TemplateRenderer

    init(settings: Settings, clock: any Clock) {
        self.settings = settings
        renderer = TemplateRenderer(locale: clock.locale, calendar: clock.calendar)
    }

    func content(for workout: Workout) -> EventContent {
        let rendered = renderer.render(settings.template(for: workout.activityType), for: workout)
        return EventContent(
            title: rendered.title,
            start: workout.start,
            end: workout.end,
            notes: settings.footerEnabled ? Footer.appending(to: rendered.notes, workoutID: workout.id) : rendered.notes
        )
    }
}
