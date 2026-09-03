//
//  CalendarSyncRules.swift
//  OrgSync
//
//  Deterministic translation between calendar events and the calendar.org
//  mirror. Kept independent of EKEventStore so format, windowing, and mapping
//  keys are fully unit-testable.
//

import Foundation

enum CalendarSyncRules {
    static let fileName = "calendar.org"
    static let managedCalendarTitle = "OrgSync"

    static let windowDays = 30

    struct Event: Equatable {
        var persistentID: String?
        var title: String
        var start: Date
        var isAllDay: Bool
    }

    static func window(now: Date = .now, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: windowDays, to: start) ?? start
        return (start, end)
    }

    static func isInWindow(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let bounds = window(now: now, calendar: calendar)
        return date >= bounds.start && date < bounds.end
    }

    static func mappingKey(persistentID: String) -> String { "id|\(persistentID)" }

    static func events(from document: OrgDocument, filePath: String = fileName) -> [Event] {
        document.todoItems(filePath: filePath).compactMap { item in
            guard let scheduled = item.scheduled, let start = scheduled.date() else { return nil }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return Event(
                persistentID: item.persistentID,
                title: title,
                start: start,
                isAllDay: !scheduled.hasTime
            )
        }
    }

    static func events(inWindowFrom document: OrgDocument, now: Date = .now) -> [Event] {
        events(from: document).filter { isInWindow($0.start, now: now) }
    }

    static func render(events: [Event], orgIsMaster: Bool = false) -> String {
        var text = "#+TITLE: Calendar\n"
        if orgIsMaster {
            text += "# Managed by OrgSync when calendar.org is the sync master.\n"
        } else {
            text += "# Read-only mirror of your calendar. Regenerated on every sync — edits here are overwritten.\n"
        }
        let sorted = events.sorted {
            $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start
        }
        for event in sorted {
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            text += "\n* TODO \(title)\n"
            if let id = event.persistentID {
                text += ":PROPERTIES:\n:ID: \(id)\n:END:\n"
            }
            let timestamp = OrgTimestamp(date: event.start, isActive: true, includeTime: !event.isAllDay)
            text += "SCHEDULED: \(timestamp.serialize())\n"
        }
        return text
    }

    enum SyncPhase: Equatable {
        case importFromIOS
        case exportToIOS
    }

    static func calendarPhases(for master: IOSSyncMasterSource) -> [SyncPhase] {
        switch master {
        case .iosApps: [.importFromIOS]
        case .orgFiles: [.exportToIOS]
        }
    }

    struct ExportUpsertPlan: Equatable {
        var orgID: String
        var usesManagedCalendar: Bool
    }

    static func exportUpsertPlans(
        orgEvents: [Event],
        mappings: [String: String],
        existingMappedEventIDs: Set<String>
    ) -> [ExportUpsertPlan] {
        orgEvents.compactMap { event in
            guard let orgID = event.persistentID else { return nil }
            let mappedID = mappings[orgID]
            let isExisting = mappedID.map { existingMappedEventIDs.contains($0) } ?? false
            return ExportUpsertPlan(orgID: orgID, usesManagedCalendar: !isExisting)
        }
    }

    static func staleMappedOrgIDs(seenOrgIDs: Set<String>, mappings: [String: String]) -> [String] {
        Array(mappings.keys.filter { !seenOrgIDs.contains($0) }).sorted()
    }
}
