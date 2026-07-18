//
//  AgendaTimeBuckets.swift
//  OrgSync
//
//  Chronological grouping for the All Agenda scope.
//

import Foundation

enum AgendaTimeBucket: String, CaseIterable, Identifiable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    case thisWeek = "This Week"
    case nextWeek = "Next Week"
    case upcoming = "Upcoming"
    case unscheduled = "Unscheduled"

    var id: String { rawValue }

    static func bucket(for date: Date?, now: Date = .now, calendar: Calendar = .current) -> AgendaTimeBucket {
        guard let date else { return .unscheduled }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today)!
        let nextMonday = calendar.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
        let weekAfterNextMonday = calendar.date(byAdding: .day, value: 7, to: nextMonday)!

        if date < tomorrow { return .today }
        if date < dayAfterTomorrow { return .tomorrow }
        if dayAfterTomorrow < nextMonday, date < nextMonday { return .thisWeek }
        if date < weekAfterNextMonday { return .nextWeek }
        return .upcoming
    }
}
