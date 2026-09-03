//
//  EventKitWritableSource.swift
//  OrgSync
//
//  Picks a writable EventKit account source for managed OrgSync calendars.
//

import EventKit

enum EventKitWritableSource {
    static func eventSource(from store: EKEventStore) -> EKSource? {
        if let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications {
            return calendar.source
        }
        return store.calendars(for: .event).first(where: { $0.allowsContentModifications })?.source
    }

    static func reminderSource(from store: EKEventStore) -> EKSource? {
        if let calendar = store.defaultCalendarForNewReminders(), calendar.allowsContentModifications {
            return calendar.source
        }
        return store.calendars(for: .reminder).first(where: { $0.allowsContentModifications })?.source
    }
}
