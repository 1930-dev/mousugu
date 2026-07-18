import Foundation

/// All user-facing strings.
///
/// Each value is a computed property that resolves via `String(localized:)`,
/// so the displayed text follows the system language at call time. Source
/// strings (the literal arguments below) are English; translations live in
/// `Localizable.xcstrings`. To add a new language, add a new locale column in
/// the catalog — no code changes required.
struct Strings {
    struct General {
        static var loading: String { String(localized: "Loading…") }
        static var noPermission: String { String(localized: "No permission") }
        static var error: String { String(localized: "Error") }
        static var noMoreEvents: String { String(localized: "No more events today") }
        static var untitledEvent: String { String(localized: "Untitled event") }
        static var join: String { String(localized: "Join") }
        static var rejoin: String { String(localized: "Rejoin") }
        static var preferences: String { String(localized: "Preferences…") }
        static var checkForUpdates: String { String(localized: "Check for updates…") }
        static var exit: String { String(localized: "Quit") }
    }

    struct Status {
        static var now: String { String(localized: "Now: ") }
        /// Format string — consumed via `String(format:)` with the minute count.
        static var inMinutes: String { String(localized: "in %dm: ") }
        /// Format string — consumed via `String(format:)` with the hour count.
        static var inHours: String { String(localized: "in %dh: ") }
        /// Format string — consumed via `String(format:)` with hour and minute counts.
        static var inHoursMinutes: String { String(localized: "in %dh %dm: ") }
        static var noEvents: String { String(localized: "No events today") }
        /// "Good work today" — the bar's sign-off once every meeting ended,
        /// in keeping with the app's Japanese name. Same in every locale.
        static var dayDone: String { String(localized: "おつかれさま") }
    }

    struct Menu {
        static var today: String { String(localized: "Today") }
    }

    struct Month {
        static var previousMonth: String { String(localized: "Previous month") }
        static var nextMonth: String { String(localized: "Next month") }
        static var goToToday: String { String(localized: "Go to today") }
        static var openCalendar: String { String(localized: "Open Calendar") }
    }

    struct Access {
        static var title: String { String(localized: "Calendar access needed") }
        static var message: String { String(localized: "Mou Sugu needs access to your calendar to show your next event. Grant access in System Settings, then reopen the app.") }
        static var openSettings: String { String(localized: "Open Privacy Settings") }
    }

    struct Settings {
        static var general: String { String(localized: "General") }
        static var calendars: String { String(localized: "Calendars") }
        static var autoStart: String { String(localized: "Start at macOS login") }
        static var hideFreeEvents: String { String(localized: "Hide events where I'm free") }
        static var joinGraceWindow: String { String(localized: "Keep Join button after meetings end") }
        static var joinGraceOff: String { String(localized: "Never") }
        static var dayDoneLabel: String { String(localized: "After the last event") }
        static var dayDoneText: String { String(localized: "Done for today") }
        static var dayDoneIconOnly: String { String(localized: "Icon only") }
    }
}
