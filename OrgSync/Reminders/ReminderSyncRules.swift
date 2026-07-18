//
//  ReminderSyncRules.swift
//  OrgSync
//
//  Deterministic translation rules between org TODOs and EventKit reminders.
//  Keeping them independent of EKEventStore makes date and recurrence behavior
//  fully unit-testable.
//

import Foundation

enum ReminderSyncRules {
    static func relevantDate(for item: OrgTodoItem) -> Date? {
        [item.deadline?.date(), item.scheduled?.date()].compactMap { $0 }.min()
    }

    static func dueDateComponents(for item: OrgTodoItem) -> DateComponents? {
        relevantDate(for: item).map {
            Calendar.current.dateComponents([.year, .month, .day], from: $0)
        }
    }

    static func priority(for priority: Character?) -> Int {
        priority == "A" ? 1 : priority == "B" ? 5 : priority == "C" ? 9 : 0
    }

    static func shouldApplyIncomingDueDate(_ date: Date, to item: OrgTodoItem) -> Bool {
        guard let existing = relevantDate(for: item) else { return true }
        return !Calendar.current.isDate(date, inSameDayAs: existing)
    }

    static func applyIncomingDueDate(_ date: Date, to headline: inout OrgHeadline) {
        if headline.planning.deadline != nil && headline.planning.scheduled == nil {
            headline.setDeadline(date: date)
        } else {
            headline.setScheduled(date: date)
        }
    }

    static func complete(_ headline: inout OrgHeadline, item: OrgTodoItem, document: OrgDocument, now: Date = .now) {
        let done = document.todoConfig.sequences.first(where: { $0.all.contains(item.keyword) })?.done.first
            ?? document.todoConfig.sequences.first?.done.first
        headline.setTodoKeyword(done, config: document.todoConfig, now: now)
    }

    static func inboxScheduledTimestamp(for date: Date) -> OrgTimestamp {
        OrgTimestamp(date: date, isActive: true, includeTime: false)
    }
}
