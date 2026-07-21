import SwiftUI
import EventKit

/// Calendr-style compact list of today's events: accent-bar rows in start
/// order, quiet separators showing the free stretch between meetings, and
/// the red now line — striking through the in-progress event at the current
/// minute's proportional position, or sitting between rows when nothing is
/// running. Opens scrolled so "now" is centered.
struct TodayEventListView: View {
    @ObservedObject var store: CalendarStore
    /// Tallest the list may grow before scrolling (screen-derived).
    let maxHeight: CGFloat

    private static let nowAnchorID = "now-anchor"

    /// Scroll anchor binding — starts on "now" so the popover opens centered
    /// on the present; resets every open since MenuBarExtra re-hosts the
    /// content view each time.
    @State private var scrolledID: String? = TodayEventListView.nowAnchorID

    /// Measured height of the list's content, so the ScrollView can be given
    /// an exact frame instead of a compressible flexible one.
    @State private var listContentHeight: CGFloat = 0

    /// Minimum free stretch that earns a gap separator row.
    private static let gapThreshold: TimeInterval = 5 * 60

    /// The first upcoming meeting today — the only future event that should
    /// show a "Unirse" button.
    private func nextUpcomingMeetingID(now: Date) -> String? {
        store.selectedDayEvents
            .first { $0.startDate > now && store.findMeetingURL(for: $0) != nil }?
            .eventIdentifier
    }

    /// Free time between this event and everything that came before it (an
    /// event nested inside a longer one yields no gap), or nil below the
    /// threshold.
    private func gapDuration(events: [EKEvent], before index: Int) -> TimeInterval? {
        guard let previousEnd = events[..<index].map(\.endDate).max() else { return nil }
        let gap = events[index].startDate.timeIntervalSince(previousEnd)
        return gap >= Self.gapThreshold ? gap : nil
    }

    var body: some View {
        // Drive `now` off the timeline, not a bare Date() captured at body-eval:
        // that value only refreshed when the store published a change, so the
        // red line froze whenever the 60s tick was suspended (App Nap, display
        // or system sleep) and reopening the popover showed a stale "now".
        // `.everyMinute` recomputes on appear and every minute while visible.
        TimelineView(.everyMinute) { context in
            listContent(now: context.date)
        }
    }

    private func listContent(now: Date) -> some View {
        let events = store.selectedDayEvents
        // The now line, join buttons and past-event dimming are meaningful
        // only while the list shows today. Browsing another day, the rows are
        // a plain schedule with none of those "current time" adornments.
        let viewingToday = Calendar.current.isDateInToday(store.selectedDay)
        let inProgressIndex = viewingToday
            ? events.firstIndex { $0.startDate <= now && $0.endDate > now }
            : nil
        // Standalone line position when nothing is running: above the first
        // event still alive; after the last row once the day is over.
        let standaloneLineIndex = viewingToday && inProgressIndex == nil
            ? (events.firstIndex { $0.endDate > now } ?? events.count)
            : nil
        let nextMeetingID = viewingToday ? nextUpcomingMeetingID(now: now) : nil

        return ScrollView {
            VStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(Array(events.enumerated()), id: \.element.eventIdentifier) { index, event in
                    if index > 0, let gap = gapDuration(events: events, before: index) {
                        GapRow(duration: gap)
                    }
                    if index == standaloneLineIndex {
                        NowLine().id(Self.nowAnchorID)
                    }
                    EventRow(
                        event: event,
                        store: store,
                        isNextUpcomingMeeting: event.eventIdentifier == nextMeetingID,
                        dimsPast: viewingToday
                    )
                    .overlay {
                        if index == inProgressIndex {
                            progressLine(for: event, now: now)
                        }
                    }
                    // The in-progress row doubles as the scroll anchor, so the
                    // popover opens centered on the running meeting.
                    .id(index == inProgressIndex ? Self.nowAnchorID : event.eventIdentifier)
                }
                if standaloneLineIndex == events.count {
                    NowLine().id(Self.nowAnchorID)
                }
            }
            .scrollTargetLayout()
            // Row margin lives inside the scroll content, keeping the scroll
            // bar in its own gutter at the popover's edge.
            .padding(.horizontal, DesignSystem.Spacing.md)
            // Report the content height so the viewport below can match it
            // exactly whenever today fits on screen.
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                listContentHeight = height
            }
        }
        .scrollPosition(id: $scrolledID, anchor: .center)
        // An explicit height, not just maxHeight: the surrounding VStack
        // compresses a flexible ScrollView once the month grid takes its
        // share. A fixed frame is non-negotiable in layout, so the list gets
        // its measured height (capped to the screen).
        .frame(height: min(max(listContentHeight, DesignSystem.Layout.eventRowHeight), maxHeight))
    }

    /// The red line crossing the running event at the fraction of it that
    /// already elapsed — Calendr's strike-through now indicator.
    private func progressLine(for event: EKEvent, now: Date) -> some View {
        GeometryReader { geometry in
            let duration = event.endDate.timeIntervalSince(event.startDate)
            let fraction = duration > 0
                ? min(max(now.timeIntervalSince(event.startDate) / duration, 0), 1)
                : 0
            NowLine()
                .offset(y: fraction * geometry.size.height
                    - DesignSystem.Layout.nowLineHeight / 2)
        }
        .allowsHitTesting(false)
    }
}

struct EventRow: View {
    let event: EKEvent
    @ObservedObject var store: CalendarStore
    let isNextUpcomingMeeting: Bool
    /// Dim this row once it's over. False when browsing a non-today schedule,
    /// where "past" carries no meaning.
    let dimsPast: Bool
    @State private var isHovered = false

    /// What kind of join button (if any) to display for this event.
    private enum JoinState {
        case hidden
        case join
        case rejoin
    }

    /// Decides whether to show the join button and which label. `Re-unirse`
    /// appears once you actually joined from here (the store tracks the
    /// clicks) instead of guessing from elapsed time.
    ///
    /// - In progress: always show — `Re-unirse` if you already joined (you
    ///   probably dropped), `Unirse` if you never did.
    /// - Ended: same labels during a configurable grace window (handy if the
    ///   meeting over-ran or someone restarted it); hidden afterwards.
    /// - Future: only on the very next upcoming meeting today — every later
    ///   one would just be noise.
    private var joinState: JoinState {
        guard store.findMeetingURL(for: event) != nil else { return .hidden }
        let now = Date()

        if event.startDate <= now && event.endDate > now {
            return store.hasJoined(event) ? .rejoin : .join
        }

        if event.endDate <= now {
            let minutesSinceEnd = now.timeIntervalSince(event.endDate) / 60
            guard minutesSinceEnd < Double(store.joinGraceMinutes) else { return .hidden }
            return store.hasJoined(event) ? .rejoin : .join
        }

        return isNextUpcomingMeeting ? .join : .hidden
    }

    /// Fully over — dimmed so in-progress and upcoming events stand out.
    /// Hovering restores full opacity to keep the row comfortable to read.
    private var isPast: Bool { event.endDate <= Date() }

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
                    .foregroundStyle(Color.primary)

                Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }

            Spacer()

            joinButton
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            // Hover deepens the row's own calendar tint — translucent, so the
            // glass keeps reading through.
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(Color(event.calendar.color).opacity(isHovered
                    ? DesignSystem.Opacity.eventRowFillHovered
                    : DesignSystem.Opacity.eventRowFill))
        )
        .opacity(dimsPast && isPast && !isHovered ? DesignSystem.Opacity.pastEvent : 1)
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
            store.markJoined(event)
            NSWorkspace.shared.open(url)
        }
    }
}

/// Free-time separator between meetings, Calendr-style: quiet dots on the
/// left, the stretch's duration on the right.
struct GapRow: View {
    let duration: TimeInterval

    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(Self.formatter.string(from: duration) ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
}

/// The current-time indicator — a red dot on the left edge with a hairline
/// running across the full width.
struct NowLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .frame(width: DesignSystem.Layout.nowDotSize,
                       height: DesignSystem.Layout.nowDotSize)
            Rectangle()
                .frame(height: DesignSystem.Layout.nowLineHeight)
        }
        .foregroundStyle(DesignSystem.Colors.todayRed)
    }
}
