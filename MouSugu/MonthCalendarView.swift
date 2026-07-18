import SwiftUI

/// One month of calendar cells, plus the exact date span they cover.
///
/// Pure date math — no EventKit — so the grid logic stays independent of the
/// store. Weeks always hold exactly 7 days; leading and trailing cells belong
/// to the adjacent months. All stepping goes through `Calendar.date(byAdding:)`
/// so 23/25-hour DST days can't drift the grid.
struct MonthGrid {
    struct Day: Identifiable {
        var id: Date { date }
        /// Start of day.
        let date: Date
        /// Year/month/day components — the key into the store's dot dictionary.
        let key: DateComponents
        let dayNumber: Int
        let isInDisplayedMonth: Bool
    }

    /// 4–6 rows of exactly 7 days.
    let weeks: [[Day]]
    /// First through last visible cell — handed to the store to fetch dots.
    let interval: DateInterval

    init(containing date: Date, calendar: Calendar = .current) {
        let month = calendar.dateInterval(of: .month, for: date)!
        // Walk back from the month's first day to the locale's week start
        // (Sunday in en-US, Monday in es).
        let leading = (calendar.component(.weekday, from: month.start)
            - calendar.firstWeekday + 7) % 7
        var day = calendar.date(byAdding: .day, value: -leading, to: month.start)!
        let gridStart = day

        var weeks: [[Day]] = []
        while day < month.end {
            var week: [Day] = []
            for _ in 0..<7 {
                week.append(Day(
                    date: day,
                    key: calendar.dateComponents([.year, .month, .day], from: day),
                    dayNumber: calendar.component(.day, from: day),
                    isInDisplayedMonth: day >= month.start && day < month.end
                ))
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            weeks.append(week)
        }
        self.weeks = weeks
        self.interval = DateInterval(start: gridStart, end: day)
    }
}

/// Itsycal-style month calendar: title and navigation, localized weekday
/// headers, and a grid of days with per-calendar event dots. Clicking a day
/// points the event list below at it; the menu bar countdown stays on today.
/// The go-to-today control snaps both the grid and the selection back.
struct MonthCalendarView: View {
    @ObservedObject var store: CalendarStore
    @Environment(\.colorScheme) private var colorScheme

    /// Muted chevron color — explicit rather than `.secondary` so it stays
    /// out of the glass's vibrancy pass.
    private var navChevronColor: Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(0.55)
    }

    /// Any date within the displayed month. MenuBarExtra re-hosts the popover
    /// content on every open, so `onAppear` resets this to the current month
    /// each time the user summons the popover.
    @State private var displayedMonth = Date()

    private var grid: MonthGrid { MonthGrid(containing: displayedMonth) }

    /// Localized "July 2026" — the template keeps the locale's word order.
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: displayedMonth)
    }

    /// Single-letter weekday symbols rotated to the locale's first weekday.
    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            header
            weekdayHeader
            daysGrid
        }
        .onAppear {
            displayedMonth = Date()
            // MenuBarExtra keeps the store alive across opens, so the list
            // could still be pointed at a day the user browsed last time —
            // reset it to today whenever the popover reappears.
            store.selectDay(Date())
            store.setMonthDotRange(grid.interval)
        }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.xxs) {
            Text(monthTitle)
                .font(.callout)
                .fontWeight(.bold)
            Spacer()
            ToolbarIconButton(systemName: "chevron.left",
                              label: Strings.Month.previousMonth,
                              iconSize: DesignSystem.Layout.monthNavIconSize,
                              buttonSize: DesignSystem.Layout.monthNavButtonSize,
                              iconColor: navChevronColor) {
                shiftMonth(by: -1)
            }
            ToolbarIconButton(systemName: "circle.fill",
                              label: Strings.Month.goToToday,
                              iconSize: DesignSystem.Layout.monthTodayDotIconSize,
                              buttonSize: DesignSystem.Layout.monthNavButtonSize,
                              iconColor: DesignSystem.Colors.todayRed) {
                goToToday()
            }
            ToolbarIconButton(systemName: "chevron.right",
                              label: Strings.Month.nextMonth,
                              iconSize: DesignSystem.Layout.monthNavIconSize,
                              buttonSize: DesignSystem.Layout.monthNavButtonSize,
                              iconColor: navChevronColor) {
                shiftMonth(by: 1)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols.indices, id: \.self) { index in
                Text(weekdaySymbols[index])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: DesignSystem.Layout.monthWeekdayHeaderHeight)
            }
        }
    }

    private var daysGrid: some View {
        VStack(spacing: 0) {
            ForEach(grid.weeks.indices, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(grid.weeks[week]) { day in
                        DayCell(day: day,
                                dotColors: store.monthDayColors[day.key] ?? [],
                                isSelected: isSelected(day),
                                onSelect: { store.selectDay(day.date) })
                    }
                }
            }
        }
    }

    /// True when `day` is the day the event list is currently showing.
    private func isSelected(_ day: MonthGrid.Day) -> Bool {
        Calendar.current.isDate(day.date, inSameDayAs: store.selectedDay)
    }

    private func shiftMonth(by months: Int) {
        guard let shifted = Calendar.current.date(
            byAdding: .month, value: months, to: displayedMonth) else { return }
        show(month: shifted)
    }

    /// The go-to-today control: jump the grid to this month *and* point the
    /// event list back at today. Plain month navigation leaves the selection
    /// alone; only this resets it.
    private func goToToday() {
        show(month: Date())
        store.selectDay(Date())
    }

    private func show(month: Date) {
        displayedMonth = month
        store.setMonthDotRange(MonthGrid(containing: month).interval)
    }
}

/// A single day in the month grid: the day number over up to
/// `monthMaxDotsPerDay` calendar-colored event dots. Today's whole cell is
/// outlined in the icon's red — the same shape the hover wash fills.
struct DayCell: View {
    let day: MonthGrid.Day
    let dotColors: [Color]
    /// Whether the event list is currently showing this day.
    let isSelected: Bool
    /// Point the event list at this day.
    let onSelect: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    /// Ring marking the browsed day when it isn't today. Explicit black/white,
    /// not `.primary`: semantic colors render in the glass's vibrancy pass.
    private var selectionColor: Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(0.4)
    }

    /// Explicit black/white, NOT `Color.primary`: semantic colors render in
    /// the glass's vibrancy pass, which composites OVER plain-color siblings
    /// regardless of SwiftUI z-order — a primary-based wash visibly covered
    /// today's red border.
    private var hoverWashColor: Color {
        (colorScheme == .dark ? Color.white : Color.black)
            .opacity(DesignSystem.Opacity.hoverWash)
    }

    /// Evaluated at render time so the highlight moves if the popover stays
    /// open across midnight.
    private var isToday: Bool { Calendar.current.isDateInToday(day.date) }

    /// Explicit colors, not `.primary`: semantic colors render in the glass's
    /// vibrancy pass, whose backing plate composites over the red border.
    private var numberColor: Color {
        let base = colorScheme == .dark ? Color.white : Color.black
        if isToday { return base }
        return day.isInDisplayedMonth ? base : base.opacity(0.3)
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            // The number is the cell's only in-flow content, so it centers
            // with equal air above and below. The dots don't participate in
            // layout — they overlay the bottom band as an ornament, the way
            // Itsycal tucks them under the date.
            Text("\(day.dayNumber)")
                .font(.callout)
                .fontWeight(isToday ? .bold : .medium)
                .foregroundStyle(numberColor)
                .frame(width: DesignSystem.Layout.monthTodayCircleSize,
                       height: DesignSystem.Layout.monthTodayCircleSize)
                .frame(maxWidth: .infinity)
                .frame(height: DesignSystem.Layout.monthDayCellHeight)
                .overlay {
                    // Today: a compact red box — wash for body plus outline —
                    // inset from the cell so it clears neighbors and its own
                    // dots instead of hugging every edge.
                    if isToday {
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                            .fill(DesignSystem.Colors.todayRed.opacity(DesignSystem.Opacity.todayCellFill))
                            .padding(.horizontal, DesignSystem.Spacing.xs + DesignSystem.Layout.monthTodayBorderWidth)
                            .padding(.vertical, DesignSystem.Spacing.xs + DesignSystem.Layout.monthTodayBorderWidth)
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                            .strokeBorder(DesignSystem.Colors.todayRed,
                                          lineWidth: DesignSystem.Layout.monthTodayBorderWidth)
                            .padding(.horizontal, DesignSystem.Spacing.xs)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                    } else if isSelected {
                        // A browsed day other than today: a quiet neutral ring,
                        // distinct from today's red box.
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                            .strokeBorder(selectionColor,
                                          lineWidth: DesignSystem.Layout.monthTodayBorderWidth)
                            .padding(.horizontal, DesignSystem.Spacing.xs)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                    }
                }
                .overlay(alignment: .bottom) {
                    HStack(spacing: DesignSystem.Spacing.xxs) {
                        ForEach(dotColors.indices, id: \.self) { index in
                            Circle()
                                .fill(dotColors[index])
                                .frame(width: DesignSystem.Layout.monthEventDotSize,
                                       height: DesignSystem.Layout.monthEventDotSize)
                        }
                    }
                    // Inset enough that today's border stroke never grazes
                    // the dots.
                    .padding(.bottom, DesignSystem.Spacing.sm + 1)
                }
                .background(
                // Neutral translucent wash, not accent: the accent circle
                // already marks today, and an opaque patch would break the
                // popover's glass.
                // Today skips the wash — the red box IS its highlight, and
                // stacking the two muddies the border.
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(isHovered && !isToday ? hoverWashColor : Color.clear)
                    .padding(.horizontal, DesignSystem.Spacing.xs)
                    .padding(.vertical, DesignSystem.Spacing.xs)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(day.date.formatted(date: .complete, time: .omitted))
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
    }
}
