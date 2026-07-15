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

    var body: some View {
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
        .frame(width: 440, height: 260)
    }
}

private struct GeneralPane: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var updater: UpdateChecker
    @AppStorage("hideFreeTimeEvents") private var hideFreeTimeEvents = true
    @AppStorage("autoStartEnabled") private var autoStartEnabled = false

    var body: some View {
        Form {
            Toggle(Strings.Settings.hideFreeEvents, isOn: $hideFreeTimeEvents)
                .onChange(of: hideFreeTimeEvents) { _, _ in
                    store.loadEvents()
                }
            Toggle(Strings.Settings.autoStart, isOn: $autoStartEnabled)
                .onChange(of: autoStartEnabled) { _, newValue in
                    toggleAutoStart(enabled: newValue)
                }
            // Only the direct/DMG channel ships Sparkle — in the App Store
            // build `isAvailable` is false and the row disappears.
            if updater.isAvailable {
                Section {
                    Button(Strings.General.checkForUpdates) {
                        updater.checkForUpdates()
                    }
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

    private var sortedCalendars: [EKCalendar] {
        store.allCalendars.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            ForEach(sortedCalendars, id: \.calendarIdentifier) { calendar in
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
        .formStyle(.grouped)
    }
}
