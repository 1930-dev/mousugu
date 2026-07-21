import SwiftUI
import EventKit

/// Calendr-style compact list of today's events: accent-bar rows in start
/// order, quiet separators showing the free stretch between meetings, and the
/// red now line. Overlapping events are laid out like Calendar's day view —
/// concurrent meetings sit side by side in columns, and a long block that wraps
/// several of them (focus time, an OOO hold) drops into a narrow spine on the
/// left so the real meetings keep the width. Opens scrolled so "now" is
/// centered.
struct TodayEventListView: View {
    @ObservedObject var store: CalendarStore
    /// Tallest the list may grow before scrolling (screen-derived).
    let maxHeight: CGFloat

    private static let nowAnchorID = "now-anchor"

    /// Width of the left spine that long background blocks collapse into.
    static let backgroundStripWidth: CGFloat = 52

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
        let groups = Self.clusters(events)
        // The now line, join buttons and past-event dimming are meaningful only
        // while the list shows today. Browsing another day, the rows are a plain
        // schedule with none of those "current time" adornments.
        let viewingToday = Calendar.current.isDateInToday(store.selectedDay)
        let nowClusterIndex = viewingToday
            ? groups.firstIndex { span($0).contains(now) }
            : nil
        // Standalone line position when nothing is running: above the first
        // cluster still alive; after the last row once the day is over.
        let standaloneLineIndex = viewingToday && nowClusterIndex == nil
            ? (groups.firstIndex { span($0).upperBound > now } ?? groups.count)
            : nil
        let nextMeetingID = viewingToday ? nextUpcomingMeetingID(now: now) : nil

        return ScrollView {
            VStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, cluster in
                    if index > 0, let gap = gap(between: groups[index - 1], and: cluster) {
                        GapRow(duration: gap)
                    }
                    if index == standaloneLineIndex {
                        NowLine().id(Self.nowAnchorID)
                    }
                    clusterView(
                        cluster,
                        isNow: index == nowClusterIndex,
                        now: now,
                        nextMeetingID: nextMeetingID,
                        viewingToday: viewingToday
                    )
                    // The in-progress cluster doubles as the scroll anchor, so
                    // the popover opens centered on what's running.
                    .id(index == nowClusterIndex ? Self.nowAnchorID : "cluster-\(index)")
                }
                if standaloneLineIndex == groups.count {
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

    /// A single cluster: one row when nothing overlaps (the common case, kept
    /// identical to the old flat list), otherwise the side-by-side band.
    @ViewBuilder
    private func clusterView(
        _ cluster: [EKEvent], isNow: Bool, now: Date,
        nextMeetingID: String?, viewingToday: Bool
    ) -> some View {
        if cluster.count == 1 {
            EventRow(
                event: cluster[0], store: store,
                isNextUpcomingMeeting: cluster[0].eventIdentifier == nextMeetingID,
                dimsPast: viewingToday
            )
            .overlay { if isNow { nowLine(over: span(cluster), now: now) } }
        } else {
            ClusterBand(
                cluster: cluster, store: store,
                nextMeetingID: nextMeetingID, dimsPast: viewingToday
            )
            .overlay { if isNow { nowLine(over: span(cluster), now: now) } }
        }
    }

    /// The red line crossing a cluster at the fraction of its span that has
    /// already elapsed — Calendr's strike-through now indicator, generalized
    /// from a single event to a whole overlap band.
    private func nowLine(over span: Range<Date>, now: Date) -> some View {
        GeometryReader { geometry in
            let duration = span.upperBound.timeIntervalSince(span.lowerBound)
            let fraction = duration > 0
                ? min(max(now.timeIntervalSince(span.lowerBound) / duration, 0), 1)
                : 0
            NowLine()
                .offset(y: fraction * geometry.size.height
                    - DesignSystem.Layout.nowLineHeight / 2)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Overlap layout

    /// The time span a cluster (or any event set) covers.
    private func span(_ events: [EKEvent]) -> Range<Date> {
        let start = events.map(\.startDate).min() ?? Date()
        let end = max(events.map(\.endDate).max() ?? start, start.addingTimeInterval(1))
        return start..<end
    }

    private func gap(between earlier: [EKEvent], and later: [EKEvent]) -> TimeInterval? {
        guard let previousEnd = earlier.map(\.endDate).max(),
              let nextStart = later.map(\.startDate).min() else { return nil }
        let free = nextStart.timeIntervalSince(previousEnd)
        return free >= Self.gapThreshold ? free : nil
    }

    /// Maximal groups of events that overlap transitively — a new group starts
    /// only once an event begins after everything before it has ended.
    static func clusters(_ events: [EKEvent]) -> [[EKEvent]] {
        let sorted = events.sorted {
            ($0.startDate, $0.endDate) < ($1.startDate, $1.endDate)
        }
        var groups: [[EKEvent]] = []
        var current: [EKEvent] = []
        var currentEnd = Date.distantPast
        for event in sorted {
            if current.isEmpty || event.startDate < currentEnd {
                current.append(event)
                currentEnd = max(currentEnd, event.endDate)
            } else {
                groups.append(current)
                current = [event]
                currentEnd = event.endDate
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// Greedy interval coloring: each event lands in the first column whose last
    /// event has already ended, so concurrent events end up in adjacent columns.
    static func columns(_ events: [EKEvent]) -> [[EKEvent]] {
        let sorted = events.sorted { $0.startDate < $1.startDate }
        var columns: [[EKEvent]] = []
        for event in sorted {
            if let index = columns.firstIndex(where: { $0.last!.endDate <= event.startDate }) {
                columns[index].append(event)
            } else {
                columns.append([event])
            }
        }
        return columns
    }
}

/// One overlap cluster laid out side by side: long wrapping blocks in a narrow
/// left spine, the remaining meetings re-clustered into time-ordered rows where
/// genuinely concurrent events sit in adjacent columns.
struct ClusterBand: View {
    let cluster: [EKEvent]
    @ObservedObject var store: CalendarStore
    let nextMeetingID: String?
    let dimsPast: Bool

    var body: some View {
        let background = cluster.filter(isBackground)
        let foreground = cluster.filter { !isBackground($0) }
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            ForEach(background, id: \.eventIdentifier) { block in
                BackgroundBlockStrip(event: block)
            }
            VStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(Array(TodayEventListView.clusters(foreground).enumerated()), id: \.offset) { _, row in
                    if row.count == 1 {
                        eventRow(row[0], compact: false)
                    } else {
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
                            ForEach(Array(TodayEventListView.columns(row).enumerated()), id: \.offset) { _, column in
                                VStack(spacing: DesignSystem.Spacing.xs) {
                                    ForEach(column, id: \.eventIdentifier) { event in
                                        eventRow(event, compact: true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: EKEvent, compact: Bool) -> EventRow {
        EventRow(
            event: event, store: store,
            isNextUpcomingMeeting: event.eventIdentifier == nextMeetingID,
            dimsPast: dimsPast, compact: compact
        )
    }

    /// A long block that fully contains two or more of the cluster's other
    /// events and isn't itself a meeting (no join link) — focus time, an OOO
    /// hold, a "busy" wrapper. It collapses into the left spine so the meetings
    /// nested inside it keep the popover's width.
    private func isBackground(_ event: EKEvent) -> Bool {
        guard store.findMeetingURL(for: event) == nil else { return false }
        let contained = cluster.filter {
            $0 !== event && event.startDate <= $0.startDate && event.endDate >= $0.endDate
        }
        return contained.count >= 2
    }
}

/// The narrow left spine a long wrapping block collapses into: its accent
/// color, a stacked title and start time, stretched to the band's full height.
struct BackgroundBlockStrip: View {
    let event: EKEvent

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
            Text(event.title)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(4)
                .foregroundStyle(Color.primary)
            Text(event.startDate.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9))
                .foregroundStyle(Color.secondary)
            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(width: TodayEventListView.backgroundStripWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(Color(event.calendar.color).opacity(DesignSystem.Opacity.eventRowFill))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: DesignSystem.Layout.eventAccentWidth / 2)
                .fill(Color(event.calendar.color))
                .frame(width: DesignSystem.Layout.eventAccentWidth)
                .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }
}

struct EventRow: View {
    let event: EKEvent
    @ObservedObject var store: CalendarStore
    let isNextUpcomingMeeting: Bool
    /// Dim this row once it's over. False when browsing a non-today schedule,
    /// where "past" carries no meaning.
    let dimsPast: Bool
    /// Column layout for a side-by-side overlap: title and time stack, the join
    /// button drops below, and the time shows just the start to fit the width.
    var compact: Bool = false
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

    /// Start–end for a full row; just the start when squeezed into a column.
    private var timeText: String {
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        if compact { return start }
        return "\(start) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        content
            .background(
                // Hover deepens the row's own calendar tint — translucent, so the
                // glass keeps reading through.
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(Color(event.calendar.color).opacity(isHovered
                        ? DesignSystem.Opacity.eventRowFillHovered
                        : DesignSystem.Opacity.eventRowFill))
            )
            .opacity(dimsPast && isPast && !isHovered ? DesignSystem.Opacity.pastEvent : 1)
            .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if compact {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                accentBar
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(event.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(Color.primary)
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                    joinButton
                }
                Spacer(minLength: 0)
            }
            .padding(DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: DesignSystem.Spacing.md) {
                accentBar
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(event.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                joinButton
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }

    private var accentBar: some View {
        RoundedRectangle(cornerRadius: DesignSystem.Layout.eventAccentWidth / 2)
            .fill(Color(event.calendar.color))
            .frame(width: DesignSystem.Layout.eventAccentWidth)
    }

    @ViewBuilder
    private var joinButton: some View {
        switch joinState {
        case .hidden:
            EmptyView()
        case .join:
            Button(Strings.General.join, action: openMeeting)
                .buttonStyle(.borderedProminent)
                .controlSize(compact ? .mini : .small)
        case .rejoin:
            Button(Strings.General.rejoin, action: openMeeting)
                .buttonStyle(.borderedProminent)
                .controlSize(compact ? .mini : .small)
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
