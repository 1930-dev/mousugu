import SwiftUI
import EventKit
import Combine

@MainActor
final class CalendarStore: ObservableObject {
    private let eventStore = EKEventStore()
    
    @Published var todayEvents: [EKEvent] = []
    @Published var allCalendars: [EKCalendar] = []
    @Published var nextEvent: EKEvent?
    @Published var countdownLabel: String = Strings.General.loading
    
    // Almacena los IDs de los calendarios que el usuario ocultó
    @AppStorage("hiddenCalendarIDs") private var hiddenCalendarIDsData: Data = Data()
    // Hide events explicitly marked with availability == .free (focus blocks,
    // reminders, etc). Default ON. Matches Fantastical/Notion Calendar behaviour.
    @AppStorage("hideFreeTimeEvents") private var hideFreeTimeEvents: Bool = true
    
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
                self?.updateCountdown()
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
                loadEvents()
            } else {
                countdownLabel = Strings.General.noPermission
            }
        } catch {
            print("Error solicitando acceso: \(error)")
            countdownLabel = Strings.General.error
        }
    }

    func loadEvents() {
        // Cargar todos los calendarios disponibles
        self.allCalendars = eventStore.calendars(for: .event)
            .sorted { $0.title < $1.title }

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        
        // Filtrar calendarios seleccionados por el usuario
        let hiddenIDs = getHiddenCalendarIDs()
        let calendarsToFetch = allCalendars.filter { !hiddenIDs.contains($0.calendarIdentifier) }
        
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendarsToFetch.isEmpty ? nil : calendarsToFetch)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { !hideFreeTimeEvents || $0.availability != .free }
            .sorted { $0.startDate < $1.startDate }
        
        self.todayEvents = events
        updateCountdown()
    }

    private func updateCountdown() {
        let now = Date()

        // Event currently in progress takes priority — shows "Ahora: …".
        if let current = todayEvents.first(where: { $0.startDate <= now && $0.endDate > now }) {
            nextEvent = current
            countdownLabel = Strings.Status.now + (current.title ?? "Evento")
            return
        }

        // Otherwise find the next upcoming event today. Recomputed every tick
        // so the bar rolls over to the next event without needing a full reload.
        let upcoming = todayEvents.first(where: { $0.startDate > now })
        nextEvent = upcoming

        guard let next = upcoming else {
            countdownLabel = Strings.General.noMoreEvents
            return
        }

        let minutes = Int(next.startDate.timeIntervalSince(now) / 60)
        if minutes < 60 {
            countdownLabel = String(format: Strings.Status.inMinutes, minutes) + (next.title ?? "")
        } else {
            countdownLabel = String(format: Strings.Status.inHours, minutes / 60) + (next.title ?? "")
        }
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
