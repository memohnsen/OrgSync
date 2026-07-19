//
//  CalendarSyncRules.swift
//  OrgSync
//
//  Deterministic rendering of calendar events into the read-only calendar.org
//  mirror. Kept independent of EKEventStore so the format and windowing are
//  fully unit-testable. The file is regenerated wholesale on every sync — any
//  local edit to it is intentionally overwritten.
//

import Foundation

enum CalendarSyncRules {
    /// Repo-relative path of the read-only mirror file.
    static let fileName = "calendar.org"

    /// How far ahead events are mirrored. Covers the agenda's maximum
    /// configurable upcoming window (30 days).
    static let windowDays = 30

    /// EventKit-independent snapshot of one calendar event.
    struct Event: Equatable {
        var title: String
        var start: Date
        var isAllDay: Bool
    }

    /// The mirror window: today (midnight) through `windowDays` from now.
    static func window(now: Date = .now, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: windowDays, to: start) ?? start
        return (start, end)
    }

    /// Renders the full calendar.org contents: one TODO headline per event,
    /// scheduled at the event start (with time unless all-day), sorted by
    /// start date then title so regeneration is stable.
    static func render(events: [Event]) -> String {
        var text = "#+TITLE: Calendar\n"
        text += "# Read-only mirror of your calendar. Regenerated on every sync — edits here are overwritten.\n"
        let sorted = events.sorted {
            $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start
        }
        for event in sorted {
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            text += "\n* TODO \(title)\n"
            let timestamp = OrgTimestamp(date: event.start, isActive: true, includeTime: !event.isAllDay)
            text += "SCHEDULED: \(timestamp.serialize())\n"
        }
        return text
    }
}
