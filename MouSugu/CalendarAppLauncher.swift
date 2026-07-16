import AppKit

/// Opens Apple Calendar, ideally positioned on a given date.
///
/// Date targeting uses Calendar's `view calendar at` Apple event — the only
/// mechanism macOS offers (the `ical://` scheme takes no date; `calshow:` is
/// iOS-only). The sandbox grants it through the
/// `com.apple.security.scripting-targets` entitlement scoped to Calendar's
/// `com.apple.iCal.UI` access group; the first use triggers the Automation
/// consent prompt. If scripting fails — consent denied, script error — fall
/// back to opening Calendar on whatever date it was already showing.
@MainActor
enum CalendarAppLauncher {
    static func open(showing date: Date) {
        let target = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = target.year, let month = target.month, let day = target.day,
              let script = NSAppleScript(source: viewCalendarScript(year: year, month: month, day: day))
        else {
            openWithoutDate()
            return
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else {
            openWithoutDate()
            return
        }
        // `activate` lives outside the granted access group, so the script
        // can't surface Calendar itself — do it from here instead.
        activateCalendar()
    }

    /// Builds the target date from integer components — locale-proof, unlike
    /// AppleScript's `date "…"` string form. Day is set to 1 first so a 31st
    /// in the current month never overflows the target month.
    private static func viewCalendarScript(year: Int, month: Int, day: Int) -> String {
        """
        tell application "Calendar"
            set d to current date
            set day of d to 1
            set year of d to \(year)
            set month of d to \(month)
            set day of d to \(day)
            set time of d to 0
            view calendar at d
        end tell
        """
    }

    /// Fallback: launch Calendar without date targeting.
    private static func openWithoutDate() {
        if let url = URL(string: "ical://") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func activateCalendar() {
        guard let appURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
