import SwiftUI
import EventKit
import ServiceManagement

/// Selected pane in the Settings window, persisted across launches per HIG
/// ("Restore the most recently viewed pane").
private enum SettingsTab: String {
    case general
    case calendars
}

/// Top-level Settings window content.
///
/// Layout follows Apple's HIG for macOS settings windows:
/// - Noncustomizable toolbar (provided by `TabView` with tab items).
/// - Each pane uses a `Form` so SwiftUI applies the standard
///   labeled-row layout, alignment, and section grouping.
/// - `.scenePadding()` matches the system-recommended root-view inset.
/// - Window sizes to its content (default behavior of the `Settings` scene).
struct CalendarSettingsView: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var updater: UpdateChecker
    @AppStorage("selectedSettingsTab") private var selection: SettingsTab = .general

    /// "1.1.1 (3)" — marketing version plus build number, straight from the
    /// bundle so both channels (direct and MAS) report what they really are.
    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // `.tabItem`/`.tag` rather than the newer `Tab(_:value:)` API, which is
            // macOS 15+; this keeps the deployment target at macOS 14.
            TabView(selection: $selection) {
                GeneralPane(store: store, updater: updater)
                    .tabItem { Label(Strings.Settings.general, systemImage: "gearshape") }
                    .tag(SettingsTab.general)
                CalendarsPane(store: store)
                    .tabItem { Label(Strings.Settings.calendars, systemImage: "calendar") }
                    .tag(SettingsTab.calendars)
            }
            .frame(width: 400, height: 290)
            Divider()
            Text(versionLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }
}

private struct GeneralPane: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var updater: UpdateChecker
    @AppStorage("hideFreeTimeEvents") private var hideFreeTimeEvents = true
    @AppStorage("autoStartEnabled") private var autoStartEnabled = false
    @AppStorage("joinGraceMinutes") private var joinGraceMinutes = 30
    @AppStorage("dayDoneStyle") private var dayDoneStyleRaw = DayDoneStyle.otsukaresama.rawValue

    /// Localized "15 min" / "1 h" labels for the grace-window picker.
    private static let graceFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        // Rows are grouped by concern and, within each section, ordered
        // alphabetically by their label.
        Form {
            Section(Strings.Settings.eventsSection) {
                Picker(Strings.Settings.dayDoneLabel, selection: $dayDoneStyleRaw) {
                    ForEach(DayDoneStyle.allCases, id: \.rawValue) { style in
                        Text(style.pickerLabel).tag(style.rawValue)
                    }
                }
                .onChange(of: dayDoneStyleRaw) { _, _ in
                    // Re-derives the bar label so a day already wrapped reflects
                    // the new choice immediately, not at the next minute tick.
                    store.loadEvents()
                }
                Toggle(Strings.Settings.hideFreeEvents, isOn: $hideFreeTimeEvents)
                    .onChange(of: hideFreeTimeEvents) { _, _ in
                        store.loadEvents()
                    }
                Picker(Strings.Settings.joinGraceWindow, selection: $joinGraceMinutes) {
                    Text(Strings.Settings.joinGraceOff).tag(0)
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Text(Self.graceFormatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)")
                            .tag(minutes)
                    }
                }
            }
            Section(Strings.Settings.appSection) {
                // Only the direct/DMG channel ships Sparkle — in the App Store
                // build `isAvailable` is false and the row disappears.
                if updater.isAvailable {
                    Button(Strings.General.checkForUpdates) {
                        updater.checkForUpdates()
                    }
                }
                Toggle(Strings.Settings.autoStart, isOn: $autoStartEnabled)
                    .onChange(of: autoStartEnabled) { _, newValue in
                        toggleAutoStart(enabled: newValue)
                    }
            }
        }
        .formStyle(.grouped)
    }

    private func toggleAutoStart(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Error configurando auto-start: \(error)")
        }
    }
}

private struct CalendarsPane: View {
    @ObservedObject var store: CalendarStore

    /// Calendars grouped by their account (`EKSource`) — the same grouping
    /// macOS Calendar shows in its sidebar. Accounts are ordered
    /// alphabetically by title, and calendars alphabetically within each.
    private var groupedCalendars: [(source: EKSource, calendars: [EKCalendar])] {
        Dictionary(grouping: store.allCalendars, by: { $0.source.sourceIdentifier })
            .values
            .map { calendars in
                (source: calendars[0].source,
                 calendars: calendars.sorted {
                     $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                 })
            }
            .sorted {
                $0.source.title.localizedCaseInsensitiveCompare($1.source.title) == .orderedAscending
            }
    }

    var body: some View {
        Form {
            ForEach(groupedCalendars, id: \.source.sourceIdentifier) { group in
                Section(sectionTitle(for: group.source)) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        calendarToggle(calendar)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Account header — the source's own title, with a fallback for the rare
    /// untitled local source.
    private func sectionTitle(for source: EKSource) -> String {
        source.title.isEmpty ? Strings.Settings.otherAccount : source.title
    }

    private func calendarToggle(_ calendar: EKCalendar) -> some View {
        Toggle(isOn: Binding(
            get: { store.isCalendarVisible(calendar) },
            set: { _ in store.toggleCalendar(calendar) }
        )) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Circle()
                    .fill(Color(calendar.color))
                    .frame(
                        width: DesignSystem.Layout.calendarDotSize,
                        height: DesignSystem.Layout.calendarDotSize
                    )
                Text(calendar.title)
            }
        }
    }
}
