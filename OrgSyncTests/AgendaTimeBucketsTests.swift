import Foundation
import Testing
@testable import OrgSync

@Suite struct AgendaTimeBucketsTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let friday = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 7, day: 17, hour: 9).date!

    @Test func groupsOverdueAndTodaysItemsTogether() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: friday)!
        #expect(AgendaTimeBucket.bucket(for: yesterday, now: friday, calendar: calendar) == .today)
        #expect(AgendaTimeBucket.bucket(for: friday, now: friday, calendar: calendar) == .today)
    }

    @Test func groupsTomorrowThroughTheEndOfWeekSeparately() {
        let saturday = calendar.date(byAdding: .day, value: 1, to: friday)!
        let sunday = calendar.date(byAdding: .day, value: 2, to: friday)!
        #expect(AgendaTimeBucket.bucket(for: saturday, now: friday, calendar: calendar) == .tomorrow)
        #expect(AgendaTimeBucket.bucket(for: sunday, now: friday, calendar: calendar) == .thisWeek)
    }

    @Test func groupsTheFollowingMondayThroughSundayAsNextWeek() {
        let monday = calendar.date(byAdding: .day, value: 3, to: friday)!
        let followingSunday = calendar.date(byAdding: .day, value: 9, to: friday)!
        #expect(AgendaTimeBucket.bucket(for: monday, now: friday, calendar: calendar) == .nextWeek)
        #expect(AgendaTimeBucket.bucket(for: followingSunday, now: friday, calendar: calendar) == .nextWeek)
    }

    @Test func groupsLaterAndUndatedItemsLast() {
        let later = calendar.date(byAdding: .day, value: 10, to: friday)!
        #expect(AgendaTimeBucket.bucket(for: later, now: friday, calendar: calendar) == .upcoming)
        #expect(AgendaTimeBucket.bucket(for: nil, now: friday, calendar: calendar) == .unscheduled)
    }
}
