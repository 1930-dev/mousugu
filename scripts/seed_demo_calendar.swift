#!/usr/bin/env swift
//
// seed_demo_calendar.swift — create (or remove) a throwaway calendar of made-up
// events, so screenshots never show anyone's real schedule.
//
// App Store screenshots are public and Mou Sugu renders event titles
// verbatim. Shooting against your own calendar publishes your meetings and the
// people in them. So: seed this, hide every other calendar in the app's
// Settings, shoot, then remove it.
//
// The calendar is created in the **local** ("On My Mac") source on purpose. An
// iCloud calendar would sync these fake meetings to every device on the account.
//
// Run:
//   swift scripts/seed_demo_calendar.swift            # create
//   swift scripts/seed_demo_calendar.swift --remove   # clean up afterwards
//
// Calendar access is granted to the process running this (Terminal, say), not to
// the script. macOS will ask the first time.

import EventKit
import Foundation

let calendarTitle = "Mou Sugu Demo"
let store = EKEventStore()
let removing = CommandLine.arguments.contains("--remove")

func requestAccess() async -> Bool {
    do {
        return try await store.requestFullAccessToEvents()
    } catch {
        print("✗ Calendar access failed: \(error.localizedDescription)")
        return false
    }
}

func existingDemoCalendars() -> [EKCalendar] {
    store.calendars(for: .event).filter { $0.title == calendarTitle }
}

func remove() throws {
    let found = existingDemoCalendars()
    guard !found.isEmpty else {
        print("Nothing to remove — no calendar titled \"\(calendarTitle)\".")
        return
    }
    for calendar in found {
        try store.removeCalendar(calendar, commit: true)
    }
    print("✓ Removed \(found.count) demo calendar(s).")
}

/// Today at the given wall-clock time, so the popover shows a plausible day.
func today(hour: Int, minute: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
}

func seed() throws {
    guard existingDemoCalendars().isEmpty else {
        print("A calendar titled \"\(calendarTitle)\" already exists. Nothing to do.")
        print("Run with --remove first if you want a fresh one.")
        return
    }
    guard let local = store.sources.first(where: { $0.sourceType == .local }) else {
        print("✗ No local (\"On My Mac\") calendar source. Refusing to write to a")
        print("  synced account — these events would land on all your devices.")
        exit(1)
    }

    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = calendarTitle
    calendar.source = local
    calendar.cgColor = NSColor(srgbRed: 0.87, green: 0.29, blue: 0.23, alpha: 1).cgColor
    try store.saveCalendar(calendar, commit: true)

    // Deliberately invented people and meetings — see the note at the top.
    let events: [(String, Date, Date, String?)] = [
        ("Standup", Date().addingTimeInterval(12 * 60), Date().addingTimeInterval(27 * 60),
         "https://meet.google.com/abc-defg-hij"),
        ("1:1 with Ana Ejemplo", today(hour: 14, minute: 0), today(hour: 14, minute: 30),
         "https://zoom.us/j/1234567890"),
        ("Design review", today(hour: 15, minute: 30), today(hour: 16, minute: 30),
         "https://meet.google.com/klm-nopq-rst"),
        ("Sprint planning", today(hour: 17, minute: 0), today(hour: 18, minute: 0), nil),
    ]

    for (title, start, end, url) in events {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        if let url { event.url = URL(string: url) }
        try store.save(event, span: .thisEvent, commit: true)
    }

    print("✓ Created \"\(calendarTitle)\" with \(events.count) events in the local source.")
    print("")
    print("Next:")
    print("  1. Open Mou Sugu → Preferences → Calendars.")
    print("  2. Untick every calendar except \"\(calendarTitle)\".")
    print("  3. Take the screenshots.")
    print("  4. swift scripts/seed_demo_calendar.swift --remove")
}

import AppKit

Task {
    guard await requestAccess() else {
        print("✗ Calendar access denied. Grant it to your terminal in")
        print("  System Settings → Privacy & Security → Calendars.")
        exit(1)
    }
    do {
        try removing ? remove() : seed()
        exit(0)
    } catch {
        print("✗ \(error.localizedDescription)")
        exit(1)
    }
}

RunLoop.main.run()
