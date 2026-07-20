//
//  TodoNotificationPlanner.swift
//  OrgSync
//
//  Pure planning logic for local TODO notifications: turns the current TODO
//  list plus the user's notification preferences into a concrete list of
//  notifications to schedule. Nothing here touches UNUserNotificationCenter or
//  the org files — the scheduler mirrors this plan into the system, and the
//  plan is recomputed from scratch whenever notes or settings change.
//

import Foundation

/// One notification the scheduler should register with the system.
struct PlannedNotification: Hashable, Identifiable {
    /// Stable identifier so replacing the pending set is idempotent.
    let id: String
    let title: String
    let body: String
    let fireDate: Date
}

enum TodoNotificationPlanner {
    /// iOS caps pending local notifications at 64 per app; stay under it and
    /// leave headroom for anything else the app schedules later.
    static let maxPlanned = 60

    /// Identifier prefix for every notification this planner owns, so the
    /// scheduler can clear exactly its own pending requests and nothing else.
    static let identifierPrefix = "todo-notification."

    /// Plan notifications for `todos`.
    ///
    /// - Timed TODOs (timestamp with a clock time) fire once per entry in
    ///   `timedOffsetsMinutes` (minutes before the event; 0 = at the event).
    /// - All-day TODOs fire once at `allDayMinutes` after midnight, or never
    ///   when `allDayMinutes` is nil.
    /// - Done TODOs, undated TODOs, and fire dates at or before `now` are
    ///   skipped. The result is sorted soonest-first and capped at `maxPlanned`.
    static func plan(
        todos: [OrgTodoItem],
        allDayMinutes: Int?,
        timedOffsetsMinutes: [Int],
        now: Date
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []

        for todo in todos where !todo.isDone {
            guard let timestamp = todo.scheduled ?? todo.deadline,
                  let eventDate = timestamp.date() else { continue }

            let kind = todo.scheduled != nil ? "Scheduled" : "Deadline"
            let file = URL(fileURLWithPath: todo.outline.filePath)
                .deletingPathExtension().lastPathComponent

            if timestamp.hasTime {
                for offset in Set(timedOffsetsMinutes) {
                    let fireDate = eventDate.addingTimeInterval(TimeInterval(-offset * 60))
                    guard fireDate > now else { continue }
                    planned.append(PlannedNotification(
                        id: identifier(for: todo, offset: offset),
                        title: todo.title,
                        body: offset == 0
                            ? "\(kind) now · \(file)"
                            : "\(kind) in \(offsetLabel(offset)) · \(file)",
                        fireDate: fireDate
                    ))
                }
            } else if let allDayMinutes {
                let fireDate = eventDate.addingTimeInterval(TimeInterval(allDayMinutes * 60))
                guard fireDate > now else { continue }
                planned.append(PlannedNotification(
                    id: identifier(for: todo, offset: nil),
                    title: todo.title,
                    body: "\(kind) today · \(file)",
                    fireDate: fireDate
                ))
            }
        }

        return planned
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maxPlanned)
            .map { $0 }
    }

    /// "5 min" / "90 min" / "1 hr" / "2 days" — used in notification bodies
    /// and the settings lead-time rows.
    static func offsetLabel(_ minutes: Int) -> String {
        if minutes >= 24 * 60, minutes % (24 * 60) == 0 {
            let days = minutes / (24 * 60)
            return days == 1 ? "1 day" : "\(days) days"
        }
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60) hr" }
        return "\(minutes) min"
    }

    private static func identifier(for todo: OrgTodoItem, offset: Int?) -> String {
        // The outline address is stable across app launches for an unchanged
        // file; when the note changes the whole plan is rebuilt anyway.
        let base = todo.persistentID ?? "\(todo.outline.filePath)#\(todo.outline.headingPath.joined(separator: "/"))#\(todo.outline.index)"
        return identifierPrefix + base + (offset.map { "@-\($0)m" } ?? "@allday")
    }
}
