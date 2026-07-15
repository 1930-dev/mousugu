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
                // the store sets an empty label in that case.
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

    /// The first upcoming meeting today — the only future event that should
    /// show a "Unirse" button. Recomputed each render so the bar/popover
    /// stay accurate as time passes.
    private var nextUpcomingMeetingID: String? {
        let now = Date()
        return store.todayEvents
            .first { $0.startDate > now && store.findMeetingURL(for: $0) != nil }?
            .eventIdentifier
    }

    /// Where the current-time line sits in the list: before the first event
    /// that hasn't ended yet — so in-progress events sit below the line and
    /// the line tops the meeting you're currently in — or after the last row
    /// once everything today is over. Recomputed each render, so the store's
    /// per-minute tick keeps it moving.
    private var nowLineIndex: Int {
        let now = Date()
        return store.todayEvents.firstIndex { $0.endDate > now } ?? store.todayEvents.count
    }

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
            eventsCard
            Divider()
                .padding(.vertical, DesignSystem.Spacing.xs)
                .padding(.horizontal, DesignSystem.Spacing.md)
            actionsCard
                .padding(.horizontal, DesignSystem.Spacing.md)
        }
        .padding(.vertical, DesignSystem.Spacing.md)
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
                .fontWeight(.semibold)
                .padding(.horizontal, DesignSystem.Spacing.md + DesignSystem.Spacing.md)
                .padding(.top, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.xs)

            if store.todayEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.xxs) {
                        ForEach(Array(store.todayEvents.enumerated()), id: \.element.eventIdentifier) { index, event in
                            if index == nowLineIndex {
                                NowLine()
                            }
                            EventRow(
                                event: event,
                                store: store,
                                isNextUpcomingMeeting: event.eventIdentifier == nextUpcomingMeetingID
                            )
                        }
                        if nowLineIndex == store.todayEvents.count {
                            NowLine()
                        }
                    }
                    // Row margin lives inside the scroll content, keeping the
                    // scroll bar in its own gutter at the popover's edge.
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }
                .frame(maxHeight: eventListMaxHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bottom section — Preferences + Quit actions, also floating on the
    /// popover's glass.
    private var actionsCard: some View {
        VStack(spacing: 0) {
            MenuOption(title: Strings.General.preferences) {
                // Accessory apps (LSUIElement) don't surface windows to the
                // front by default — activate before opening Settings so it
                // appears above the active app.
                NSApp.activate(ignoringOtherApps: true)
                Self.centerNextKeyWindow()
                openSettings()
            }
            Divider()
                .padding(.vertical, DesignSystem.Spacing.xs)
            MenuOption(title: Strings.General.exit) {
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

/// Apple-Calendar-style current-time indicator — a tiny red dot and hairline
/// that separates the events that already started from the ones still to come.
struct NowLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .frame(width: DesignSystem.Layout.nowDotSize,
                       height: DesignSystem.Layout.nowDotSize)
            Rectangle()
                .frame(height: DesignSystem.Layout.nowLineHeight)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, DesignSystem.Spacing.xs)
    }
}

struct EventRow: View {
    let event: EKEvent
    @ObservedObject var store: CalendarStore
    let isNextUpcomingMeeting: Bool
    @State private var isHovered = false

    /// What kind of join button (if any) to display for this event.
    private enum JoinState {
        case hidden
        case join
        case rejoin
    }

    /// Decides whether to show the join button and which label.
    ///
    /// - In progress: always show; `Re-unirse` once >5 min in (you almost
    ///   certainly already joined and dropped) so it nudges differently from
    ///   the initial join.
    /// - Past: keep `Unirse` for a 1h grace window (handy if the meeting
    ///   over-ran or someone restarted it); hide after.
    /// - Future: only on the very next upcoming meeting today — every later
    ///   one would just be noise.
    private var joinState: JoinState {
        guard store.findMeetingURL(for: event) != nil else { return .hidden }
        let now = Date()

        if event.startDate <= now && event.endDate > now {
            let minutesIn = now.timeIntervalSince(event.startDate) / 60
            return minutesIn > 5 ? .rejoin : .join
        }

        if event.endDate <= now {
            let minutesSinceEnd = now.timeIntervalSince(event.endDate) / 60
            return minutesSinceEnd < 60 ? .join : .hidden
        }

        return isNextUpcomingMeeting ? .join : .hidden
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            RoundedRectangle(cornerRadius: DesignSystem.Layout.eventAccentWidth / 2)
                .fill(Color(event.calendar.color))
                .frame(width: DesignSystem.Layout.eventAccentWidth)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(isHovered
                        ? Color(nsColor: .selectedMenuItemTextColor)
                        : Color.primary)

                Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(isHovered
                        ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.85)
                        : Color.secondary)
            }

            Spacer()

            joinButton
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(isHovered
                    ? Color(nsColor: .controlAccentColor)
                    : Color(event.calendar.color).opacity(0.12))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var joinButton: some View {
        switch joinState {
        case .hidden:
            EmptyView()
        case .join:
            Button(Strings.General.join, action: openMeeting)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .rejoin:
            Button(Strings.General.rejoin, action: openMeeting)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private func openMeeting() {
        if let url = store.findMeetingURL(for: event) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A native-macOS-menu-item-style row, sized for the Control-Center-style
/// actions card.
///
/// Full-width hit area with an inset, rounded hover highlight that uses the
/// neutral gray (`unemphasizedSelectedContentBackgroundColor`) macOS reserves
/// for low-emphasis selection — same look as the sidebars in System Settings,
/// Notes, and Finder. The small outer inset assumes the parent is a card
/// (which already provides outer breathing room); the inset stays small so
/// the highlight nearly fills the card the way Control Center tiles do.
struct MenuOption: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Font(NSFont.menuFont(ofSize: 0)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .foregroundStyle(isHovered
                    ? Color(nsColor: .selectedMenuItemTextColor)
                    : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .fill(isHovered ? Color(nsColor: .controlAccentColor) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
