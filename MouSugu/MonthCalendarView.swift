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
/// opens Calendar.app positioned on it — the popover's list stays on today.
struct MonthCalendarView: View {
    @ObservedObject var store: CalendarStore

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
        VStack(spacing: DesignSystem.Spacing.xs) {
            header
            weekdayHeader
            daysGrid
        }
        .onAppear {
            displayedMonth = Date()
            store.setMonthDotRange(grid.interval)
        }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.xxs) {
            Text(monthTitle)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            ToolbarIconButton(systemName: "chevron.left",
                              label: Strings.Month.previousMonth) {
                shiftMonth(by: -1)
            }
            ToolbarIconButton(systemName: "circle.fill",
                              label: Strings.Month.goToToday,
                              iconSize: DesignSystem.Layout.monthTodayDotIconSize) {
                show(month: Date())
            }
            ToolbarIconButton(systemName: "chevron.right",
                              label: Strings.Month.nextMonth) {
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
            }
        }
    }

    private var daysGrid: some View {
        VStack(spacing: 0) {
            ForEach(grid.weeks.indices, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(grid.weeks[week]) { day in
                        DayCell(day: day,
                                dotColors: store.monthDayColors[day.key] ?? [])
                    }
                }
            }
        }
    }

    private func shiftMonth(by months: Int) {
        guard let shifted = Calendar.current.date(
            byAdding: .month, value: months, to: displayedMonth) else { return }
        show(month: shifted)
    }

    private func show(month: Date) {
        displayedMonth = month
        store.setMonthDotRange(MonthGrid(containing: month).interval)
    }
}

/// A single day in the month grid: the day number (today gets a filled accent
/// circle) over up to `monthMaxDotsPerDay` calendar-colored event dots.
struct DayCell: View {
    let day: MonthGrid.Day
    let dotColors: [Color]
    @State private var isHovered = false

    /// Evaluated at render time so the highlight moves if the popover stays
    /// open across midnight.
    private var isToday: Bool { Calendar.current.isDateInToday(day.date) }

    private var numberColor: Color {
        if isToday { return Color(nsColor: .selectedMenuItemTextColor) }
        return day.isInDisplayedMonth ? .primary : Color(nsColor: .tertiaryLabelColor)
    }

    var body: some View {
        Button {
            CalendarAppLauncher.open(showing: day.date)
        } label: {
            VStack(spacing: DesignSystem.Spacing.xxs) {
                // Phantom counterweight for the dot row below, so the day
                // number sits dead-center in the cell instead of riding high.
                Color.clear
                    .frame(height: DesignSystem.Layout.monthEventDotSize)
                Text("\(day.dayNumber)")
                    .font(.caption)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(numberColor)
                    .frame(width: DesignSystem.Layout.monthTodayCircleSize,
                           height: DesignSystem.Layout.monthTodayCircleSize)
                    .background(
                        Circle()
                            .fill(isToday ? Color(nsColor: .controlAccentColor) : .clear)
                    )
                // Constant-height dot row so day numbers align across weeks.
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    ForEach(dotColors.indices, id: \.self) { index in
                        Circle()
                            .fill(dotColors[index])
                            .frame(width: DesignSystem.Layout.monthEventDotSize,
                                   height: DesignSystem.Layout.monthEventDotSize)
                    }
                }
                .frame(height: DesignSystem.Layout.monthEventDotSize)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DesignSystem.Layout.monthDayCellHeight)
            .background(
                // Neutral translucent wash, not accent: the accent circle
                // already marks today, and an opaque patch would break the
                // popover's glass.
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(isHovered
                        ? Color.primary.opacity(DesignSystem.Opacity.hoverWash)
                        : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(day.date.formatted(date: .complete, time: .omitted))
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
    }
}
