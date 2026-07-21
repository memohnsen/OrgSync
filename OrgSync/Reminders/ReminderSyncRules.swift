//
//  ReminderSyncRules.swift
//  OrgSync
//
//  Deterministic translation rules between org TODOs and EventKit reminders.
//  Keeping them independent of EKEventStore makes date and recurrence behavior
//  fully unit-testable.
//

import EventKit
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

    /// Translate the Org repeater attached to the date mirrored to Reminders.
    /// EventKit has no hourly recurrence, so hourly Org tasks remain local-only.
    static func recurrenceRules(for item: OrgTodoItem) -> [EKRecurrenceRule]? {
        guard let repeater = repeatingTimestamp(for: item)?.repeater,
              let frequency = recurrenceFrequency(for: repeater.unit) else { return nil }
        return [EKRecurrenceRule(recurrenceWith: frequency, interval: repeater.value, end: nil)]
    }

    /// Imports the first standard Reminders recurrence as an Org `+` repeater.
    static func repeater(from reminder: EKReminder) -> OrgRepeater? {
        guard let rule = reminder.recurrenceRules?.first else { return nil }
        let unit: OrgInterval
        switch rule.frequency {
        case .daily: unit = .day
        case .weekly: unit = .week
        case .monthly: unit = .month
        case .yearly: unit = .year
        @unknown default: return nil
        }
        return OrgRepeater(kind: .cumulate, value: max(1, rule.interval), unit: unit)
    }

    static func shouldApplyIncomingRepeater(_ repeater: OrgRepeater, to item: OrgTodoItem) -> Bool {
        repeatingTimestamp(for: item)?.repeater != repeater
    }

    static func applyIncomingRepeater(_ repeater: OrgRepeater, to headline: inout OrgHeadline) {
        if headline.planning.deadline != nil && headline.planning.scheduled == nil {
            headline.planning.deadline?.repeater = repeater
        } else {
            headline.planning.scheduled?.repeater = repeater
        }
        headline.planning.raw = nil
    }

    static func shouldApplyIncomingDueDate(_ date: Date, to item: OrgTodoItem) -> Bool {
        guard let existing = relevantDate(for: item) else { return true }
        return !Calendar.current.isDate(date, inSameDayAs: existing)
    }

    static func applyIncomingDueDate(_ date: Date, to headline: inout OrgHeadline) {
        if headline.planning.deadline != nil && headline.planning.scheduled == nil {
            headline.setDeadline(timestampReplacingDate(headline.planning.deadline, with: date))
        } else {
            headline.setScheduled(timestampReplacingDate(headline.planning.scheduled, with: date))
        }
    }

    /// Keep repeater/warning/time from the existing org timestamp when only the
    /// day changes (e.g. Reminders advances a recurring due date). Dropping the
    /// repeater would make the next outbound pass wipe EventKit recurrence too.
    private static func timestampReplacingDate(_ existing: OrgTimestamp?, with date: Date) -> OrgTimestamp {
        var ts = OrgTimestamp(date: date, isActive: existing?.isActive ?? true, includeTime: false)
        guard let existing else { return ts }
        ts.isActive = existing.isActive
        if existing.hasTime {
            ts.startHour = existing.startHour
            ts.startMinute = existing.startMinute
            ts.endHour = existing.endHour
            ts.endMinute = existing.endMinute
        }
        ts.repeater = existing.repeater
        ts.warning = existing.warning
        return ts
    }

    static func complete(_ headline: inout OrgHeadline, item: OrgTodoItem, document: OrgDocument, now: Date = .now) {
        let done = document.todoConfig.allKeywords.first {
            $0.caseInsensitiveCompare("DONE") == .orderedSame
        } ?? document.todoConfig.sequences.first(where: { $0.all.contains(item.keyword) })?.done.first
            ?? document.todoConfig.sequences.first?.done.first
        headline.setTodoKeyword(done, config: document.todoConfig, now: now)
    }

    static func inboxScheduledTimestamp(for date: Date) -> OrgTimestamp {
        OrgTimestamp(date: date, isActive: true, includeTime: false)
    }

    /// Used while importing a brand-new reminder into inbox.org.
    static func appending(repeater: OrgRepeater, toLastScheduledTimestampIn text: String) -> String {
        guard let range = text.range(of: ">", options: .backwards) else { return text }
        return text.replacingCharacters(in: range, with: " \(repeater.text)>")
    }

    private static func repeatingTimestamp(for item: OrgTodoItem) -> OrgTimestamp? {
        let timestamps = [item.deadline, item.scheduled].compactMap { $0 }
        return timestamps.first(where: { $0.repeater != nil })
    }

    private static func recurrenceFrequency(for unit: OrgInterval) -> EKRecurrenceFrequency? {
        switch unit {
        case .day: .daily
        case .week: .weekly
        case .month: .monthly
        case .year: .yearly
        case .hour: nil
        }
    }
}
