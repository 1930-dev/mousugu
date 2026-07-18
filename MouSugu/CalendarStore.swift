import SwiftUI
import EventKit
import Combine

/// What the menu bar shows once every meeting today has ended. Persisted by
/// raw value under "dayDoneStyle"; おつかれさま is the default sign-off.
enum DayDoneStyle: String, CaseIterable {
    case otsukaresama
    case doneForToday
    case checkmark
    case iconOnly

    /// The text next to the bar icon (empty collapses the bar to the icon).
    var barLabel: String {
        switch self {
        case .otsukaresama: Strings.Status.dayDone
        case .doneForToday: Strings.Settings.dayDoneText
        case .checkmark: "✓"
        case .iconOnly: ""
        }
    }

    /// Row title in the Settings picker — the bar text itself, so the choice
    /// previews what it does; only icon-only needs a descriptive name.
    var pickerLabel: String {
        self == .iconOnly ? Strings.Settings.dayDoneIconOnly : barLabel
    }
}

@MainActor
final class CalendarStore: ObservableObject {
    private let eventStore = EKEventStore()
    
    @Published var todayEvents: [EKEvent] = []
    /// Start-of-day the popover list is showing. Defaults to today; the month
    /// grid repoints it via `selectDay`, and it snaps back to today on day
    /// rollover and on each popover open. The menu bar countdown never follows
    /// it — only the list does.
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    /// Events for `selectedDay` — what the popover list renders. Identical to
    /// `todayEvents` while the selection is today.
    @Published private(set) var selectedDayEvents: [EKEvent] = []
    @Published var allCalendars: [EKCalendar] = []
    @Published var nextEvent: EKEvent?
    @Published var countdownLabel: String = Strings.General.loading
    /// `true` when calendar access was denied or restricted, so the popover can
    /// offer a way to fix it instead of showing an empty list.
    @Published var accessDenied: Bool = false
    /// Calendar colors for each day visible in the month grid, keyed by
    /// year/month/day components. Unlike the today list, all-day events count
    /// here — a dot means "something happens this day".
    @Published private(set) var monthDayColors: [DateComponents: [Color]] = [:]

    /// Date span of the month grid currently on screen. Retained so calendar
    /// changes and the day rollover refresh the dots without the view having
    /// to ask again.
    private var monthDotInterval: DateInterval?

    /// Start-of-day of the currently loaded event window. Lets the per-minute
    /// tick detect a day rollover and reload, rather than staying stuck on the
    /// previous day until an external EventKit change happens to fire.
    private var loadedDay = Date.distantPast
    
    // Almacena los IDs de los calendarios que el usuario ocultó
    @AppStorage("hiddenCalendarIDs") private var hiddenCalendarIDsData: Data = Data()
    // Hide events explicitly marked with availability == .free (focus blocks,
    // reminders, etc). Default ON. Matches Fantastical/Notion Calendar behaviour.
    @AppStorage("hideFreeTimeEvents") private var hideFreeTimeEvents: Bool = true
    /// Minutes a finished meeting keeps its join button (0 hides immediately).
    /// User-configurable from Settings → General.
    @AppStorage("joinGraceMinutes") var joinGraceMinutes: Int = 30
    /// Menu bar sign-off once the day's meetings ended (Settings → General).
    @AppStorage("dayDoneStyle") private var dayDoneStyleRaw: String = DayDoneStyle.otsukaresama.rawValue

    /// Events actually joined from the popover today — the real signal behind
    /// Unirse vs Re-unirse. In-memory only; cleared on day rollover.
    @Published private var joinedEventKeys: Set<String> = []
    
    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupObservers()
        Task {
            await requestAccessAndLoad()
        }
    }

    private func setupObservers() {
        NotificationCenter.default
            .publisher(for: .EKEventStoreChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadEvents()
                }
            }
            .store(in: &cancellables)

        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    /// Per-minute tick. Reloads the whole window when the calendar day rolled
    /// over (so tomorrow's events appear on their own), otherwise just refreshes
    /// the countdown.
    private func tick() {
        if Calendar.current.startOfDay(for: Date()) != loadedDay {
            loadEvents()
        } else {
            updateCountdown()
        }
    }

    func requestAccessAndLoad() async {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
            
            if granted {
                accessDenied = false
                loadEvents()
            } else {
                accessDenied = true
                countdownLabel = Strings.General.noPermission
            }
        } catch {
            print("Error solicitando acceso: \(error)")
            accessDenied = true
            countdownLabel = Strings.General.error
        }
    }

    func loadEvents() {
        // Cargar todos los calendarios disponibles
        self.allCalendars = eventStore.calendars(for: .event)
            .sorted { $0.title < $1.title }

        let today = Calendar.current.startOfDay(for: Date())
        if today != loadedDay {
            // A new calendar day began: the join history and any day the user
            // was browsing belong to yesterday — snap both back to today.
            joinedEventKeys.removeAll()
            selectedDay = today
        }
        self.loadedDay = today

        self.todayEvents = events(forDayStarting: today)
        self.selectedDayEvents = selectedDay == today
            ? todayEvents
            : events(forDayStarting: selectedDay)

        updateCountdown()
        loadMonthDots()
    }

    /// Visible, non-all-day events for the single day starting at `dayStart`,
    /// with the same calendar-visibility and free-time filters the bar uses,
    /// in stable start order. Reads `allCalendars`, so callers must refresh it
    /// first.
    private func events(forDayStarting dayStart: Date) -> [EKEvent] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let hiddenIDs = getHiddenCalendarIDs()
        let calendarsToFetch = allCalendars.filter { !hiddenIDs.contains($0.calendarIdentifier) }
        let predicate = eventStore.predicateForEvents(
            withStart: dayStart, end: end,
            calendars: calendarsToFetch.isEmpty ? nil : calendarsToFetch)
        return eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { !hideFreeTimeEvents || $0.availability != .free }
            // Simultaneous starts: the event that ends first goes first, then
            // title as the final tiebreaker — Swift's sort isn't stable, so a
            // start-only comparator shuffles equal starts on every reload.
            .sorted {
                ($0.startDate, $0.endDate, $0.title ?? "")
                    < ($1.startDate, $1.endDate, $1.title ?? "")
            }
    }

    /// Point the popover list at `date`'s day. The menu bar countdown stays on
    /// today; only the list follows the selection. No-op when the day is
    /// already selected.
    func selectDay(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        guard day != selectedDay else { return }
        selectedDay = day
        selectedDayEvents = day == loadedDay ? todayEvents : events(forDayStarting: day)
    }

    func markJoined(_ event: EKEvent) {
        joinedEventKeys.insert(joinKey(for: event))
    }

    func hasJoined(_ event: EKEvent) -> Bool {
        joinedEventKeys.contains(joinKey(for: event))
    }

    /// Recurring events share their `eventIdentifier` across occurrences, so
    /// the start date disambiguates two instances on the same day.
    private func joinKey(for event: EKEvent) -> String {
        "\(event.eventIdentifier ?? "")-\(event.startDate.timeIntervalSince1970)"
    }

    /// Called by the month view whenever the displayed month changes.
    func setMonthDotRange(_ interval: DateInterval) {
        monthDotInterval = interval
        // Deferred: this is called from `onAppear`, mid view-update, and
        // publishing `monthDayColors` synchronously there is undefined
        // behavior SwiftUI may drop — the prime suspect for a popover that
        // once came up with no dots at all.
        Task { @MainActor in
            self.loadMonthDots()
        }
    }

    /// Recomputes `monthDayColors` for the current grid span with a single
    /// EventKit query. Applies the same visibility filters as `loadEvents()`
    /// except the all-day one, and marks every day a multi-day event covers.
    private func loadMonthDots() {
        guard let interval = monthDotInterval, !accessDenied else { return }

        let hiddenIDs = getHiddenCalendarIDs()
        let calendarsToFetch = eventStore.calendars(for: .event)
            .filter { !hiddenIDs.contains($0.calendarIdentifier) }
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: calendarsToFetch.isEmpty ? nil : calendarsToFetch
        )
        let events = eventStore.events(matching: predicate)
            .filter { !hideFreeTimeEvents || $0.availability != .free }

        let cal = Calendar.current
        var colors: [DateComponents: [Color]] = [:]
        var seenCalendars: [DateComponents: Set<String>] = [:]
        for event in events {
            var day = cal.startOfDay(for: max(event.startDate, interval.start))
            let last = min(event.endDate, interval.end)
            repeat {
                let key = cal.dateComponents([.year, .month, .day], from: day)
                // One dot per calendar per day, capped so busy days don't
                // overflow the cell.
                if colors[key, default: []].count < DesignSystem.Layout.monthMaxDotsPerDay,
                   seenCalendars[key, default: []].insert(event.calendar.calendarIdentifier).inserted {
                    colors[key, default: []].append(Color(event.calendar.color))
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            } while day < last
        }
        monthDayColors = colors
    }

    private func updateCountdown() {
        let now = Date()

        // Event currently in progress takes priority — shows "Ahora: …".
        if let current = todayEvents.first(where: { $0.startDate <= now && $0.endDate > now }) {
            nextEvent = current
            countdownLabel = Strings.Status.now + eventTitle(current)
            return
        }

        // Otherwise find the next upcoming event today. Recomputed every tick
        // so the bar rolls over to the next event without needing a full reload.
        let upcoming = todayEvents.first(where: { $0.startDate > now })
        nextEvent = upcoming

        guard let next = upcoming else {
            // Day wrapped after actual meetings: the user-chosen sign-off. A
            // day with no events at all keeps the bar collapsed to just the
            // icon; there is nothing to sign off from.
            let style = DayDoneStyle(rawValue: dayDoneStyleRaw) ?? .otsukaresama
            countdownLabel = todayEvents.isEmpty ? "" : style.barLabel
            return
        }

        let minutes = Int(next.startDate.timeIntervalSince(now) / 60)
        if minutes < 60 {
            countdownLabel = String(format: Strings.Status.inMinutes, minutes) + eventTitle(next)
        } else if minutes % 60 == 0 {
            countdownLabel = String(format: Strings.Status.inHours, minutes / 60) + eventTitle(next)
        } else {
            // Truncating to hours alone reads wrong — 1h51m is not "in 1h".
            countdownLabel = String(format: Strings.Status.inHoursMinutes, minutes / 60, minutes % 60) + eventTitle(next)
        }
    }

    /// Max characters of an event title in the menu bar label — the chip
    /// truncates here because MenuBarExtra ignores layout modifiers on its
    /// label and would otherwise let long titles eat the whole bar.
    private static let maxBarTitleLength = 24

    /// Event title for the menu bar label: localized fallback when untitled,
    /// truncated with an ellipsis when long.
    private func eventTitle(_ event: EKEvent) -> String {
        let title = event.title ?? ""
        let resolved = title.isEmpty ? Strings.General.untitledEvent : title
        guard resolved.count > Self.maxBarTitleLength else { return resolved }
        return resolved.prefix(Self.maxBarTitleLength)
            .trimmingCharacters(in: .whitespaces) + "…"
    }

    func toggleCalendar(_ calendar: EKCalendar) {
        var hiddenIDs = getHiddenCalendarIDs()
        if hiddenIDs.contains(calendar.calendarIdentifier) {
            hiddenIDs.remove(calendar.calendarIdentifier)
        } else {
            hiddenIDs.insert(calendar.calendarIdentifier)
        }
        saveHiddenCalendarIDs(hiddenIDs)
        loadEvents()
    }
    
    func isCalendarVisible(_ calendar: EKCalendar) -> Bool {
        let hiddenIDs = getHiddenCalendarIDs()
        return !hiddenIDs.contains(calendar.calendarIdentifier)
    }



    private func getHiddenCalendarIDs() -> Set<String> {
        guard let ids = try? JSONDecoder().decode(Set<String>.self, from: hiddenCalendarIDsData) else {
            return []
        }
        return ids
    }

    private func saveHiddenCalendarIDs(_ ids: Set<String>) {
        if let encoded = try? JSONEncoder().encode(ids) {
            hiddenCalendarIDsData = encoded
        }
    }

    func findMeetingURL(for event: EKEvent) -> URL? {
        if let url = event.url, isMeetingURL(url) {
            return url
        }
        if let notes = event.notes {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector?.matches(in: notes, options: [], range: NSRange(location: 0, length: notes.utf16.count))
            for match in matches ?? [] {
                if let url = match.url, isMeetingURL(url) {
                    return url
                }
            }
        }
        return nil
    }

    private func isMeetingURL(_ url: URL) -> Bool {
        let meetingDomains = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com"]
        return meetingDomains.contains { url.host?.contains($0) == true }
    }
}
