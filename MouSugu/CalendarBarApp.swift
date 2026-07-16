import SwiftUI
import EventKit

@main
struct CalendarBarApp: App {
    @StateObject private var store = CalendarStore()
    @StateObject private var updater = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            MainMenuView(store: store)
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "calendar")
                // Collapse to just the icon when idle (no upcoming event today);
                // the store sets an empty label in that case. Long titles are
                // truncated by the store — MenuBarExtra ignores layout
                // modifiers on its label, so a maxWidth frame here is inert.
                if !store.countdownLabel.isEmpty {
                    Text(store.countdownLabel)
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            CalendarSettingsView(store: store, updater: updater)
        }
        .defaultPosition(.center)
    }
}

struct MainMenuView: View {
    @ObservedObject var store: CalendarStore
    @Environment(\.openSettings) private var openSettings

    /// Tallest the event list may grow before scrolling: the screen's visible
    /// height minus the popover's fixed chrome, so the scroll bar only shows
    /// up when today genuinely doesn't fit on screen.
    private var eventListMaxHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height
            ?? DesignSystem.Layout.eventListMaxHeight
        return max(DesignSystem.Layout.eventListMaxHeight,
                   visibleHeight - DesignSystem.Layout.popoverChromeAllowance)
    }

    var body: some View {
        // Horizontal margins live on each section rather than on this stack,
        // so the ScrollView reaches the popover's edge and its scroll bar
        // hugs the window border instead of overlapping the event rows.
        VStack(spacing: 0) {
            MonthCalendarView(store: store)
                .padding(.horizontal, DesignSystem.Spacing.md)
            Divider()
                .padding(.vertical, DesignSystem.Spacing.xs)
                .padding(.horizontal, DesignSystem.Spacing.md)
            eventsCard
            Divider()
                .padding(.vertical, DesignSystem.Spacing.xs)
                .padding(.horizontal, DesignSystem.Spacing.md)
            actionsCard
                .padding(.horizontal, DesignSystem.Spacing.md)
        }
        // Less air on top than on the bottom: the month header carries its
        // own line height, while the toolbar icons need the full margin.
        .padding(.top, DesignSystem.Spacing.xs)
        .padding(.bottom, DesignSystem.Spacing.md)
        .frame(width: DesignSystem.Layout.popoverWidth)
        // Sets the popover window's background material at the chrome level
        // (not an overlay), so MenuBarExtra's default chrome doesn't override
        // it. `.ultraThinMaterial` is the most translucent system material —
        // shows the wallpaper through, exactly like Control Center.
        .containerBackground(.ultraThinMaterial, for: .window)
    }

    /// Registers a one-shot observer that centers the next window to become
    /// key on screen. `Settings` scene's `.defaultPosition(.center)` only
    /// applies the first time the window opens — after that macOS remembers
    /// whatever position the user moved it to. This forces a re-center on
    /// every invocation of Preferences.
    static func centerNextKeyWindow() {
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let observer { NotificationCenter.default.removeObserver(observer) }
            (notification.object as? NSWindow)?.center()
        }
    }

    /// Top section — today's events list, floating directly on the popover's
    /// translucent glass.
    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.accessDenied {
                accessDeniedState
            } else {
                todayEventsList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Header + today's events (or the empty state), shown once calendar access
    /// is granted.
    private var todayEventsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.Menu.today)
                .font(.subheadline)
                // Same x as the month title and the row cards' left edge, so
                // both section headers sit on one vertical line.
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.top, DesignSystem.Spacing.xs)
                .padding(.bottom, DesignSystem.Spacing.xs)

            if store.todayEvents.isEmpty {
                emptyState
            } else {
                TodayEventListView(store: store, maxHeight: eventListMaxHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bottom toolbar — quick actions as compact icons, floating on the
    /// popover's glass. Quit sits isolated on the right, away from misclicks.
    private var actionsCard: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ToolbarIconButton(systemName: "gearshape",
                              label: Strings.General.preferences) {
                // Accessory apps (LSUIElement) don't surface windows to the
                // front by default — activate before opening Settings so it
                // appears above the active app.
                NSApp.activate(ignoringOtherApps: true)
                Self.centerNextKeyWindow()
                openSettings()
            }
            ToolbarIconButton(systemName: "calendar",
                              label: Strings.Month.openCalendar) {
                CalendarAppLauncher.open(showing: Date())
            }
            Spacer()
            ToolbarIconButton(systemName: "power",
                              label: Strings.General.exit) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(Strings.General.noMoreEvents)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xl)
    }

    /// Shown when calendar access was denied — explains the problem and links
    /// straight to the Privacy pane so the user isn't stuck on an empty list.
    private var accessDeniedState: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(Strings.Access.title)
                .font(.callout)
                .fontWeight(.semibold)
            Text(Strings.Access.message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(Strings.Access.openSettings) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DesignSystem.Spacing.md + DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.xl)
    }
}

/// A compact icon button for the popover's toolbar and the month header.
///
/// Square hit area with a translucent hover wash that plays along with the
/// popover's glass. The label doubles as tooltip and accessibility label,
/// since the icon is the only visible cue.
struct ToolbarIconButton: View {
    let systemName: String
    let label: String
    let iconSize: CGFloat
    let buttonSize: CGFloat
    let iconColor: Color?
    let action: () -> Void
    @State private var isHovered = false

    init(systemName: String,
         label: String,
         iconSize: CGFloat = DesignSystem.Layout.toolbarIconSize,
         buttonSize: CGFloat = DesignSystem.Layout.toolbarButtonSize,
         iconColor: Color? = nil,
         action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.iconSize = iconSize
        self.buttonSize = buttonSize
        self.iconColor = iconColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(iconColor ?? Color.primary)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .fill(isHovered
                            ? Color.primary.opacity(DesignSystem.Opacity.hoverWash)
                            : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// AppKit-backed translucent background.
///
/// `NSVisualEffectView` with `.underWindowBackground` gives the most
/// translucent glass effect available — matches the wallpaper-show-through
/// look of Notion Calendar / Fantastical. SwiftUI's `.ultraThinMaterial` is
/// composed *on top of* the `MenuBarExtra`'s default chrome, which dampens
/// translucency; this view replaces that chrome entirely.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
