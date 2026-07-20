//
//  AgendaDateWindowTests.swift
//  OrgSyncTests
//
//  The shared window definition behind the Agenda tab, Siri intents, and the
//  widget. These pin the boundary semantics so the surfaces can't drift.
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct AgendaDateWindowTests {
    private let calendar = Calendar.current
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 15))!

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            .addingTimeInterval(TimeInterval(hour * 3600))
    }

    @Test func todayIncludesOverdueAndAllOfTodayButNotTomorrow() {
        let window = AgendaDateWindow.todayAndOverdue
        #expect(window.contains(day(-30), now: now))
        #expect(window.contains(day(0, hour: 0), now: now))
        #expect(window.contains(day(0, hour: 23), now: now))
        #expect(!window.contains(day(1, hour: 0), now: now))
    }

    @Test func upcomingWindowBoundsAreExclusiveOfTheEndDay() {
        let window = AgendaDateWindow.upcoming(days: 7, includesOverdue: true)
        #expect(window.contains(day(0), now: now))
        #expect(window.contains(day(6), now: now))
        #expect(!window.contains(day(7), now: now))
    }

    @Test func overdueInclusionIsExplicit() {
        #expect(AgendaDateWindow.upcoming(days: 7, includesOverdue: true).contains(day(-3), now: now))
        #expect(!AgendaDateWindow.upcoming(days: 7, includesOverdue: false).contains(day(-3), now: now))
        // Today itself is not "overdue": both variants include it.
        #expect(AgendaDateWindow.upcoming(days: 7, includesOverdue: false).contains(day(0, hour: 0), now: now))
    }

    @Test func allIsUnbounded() {
        #expect(AgendaDateWindow.all.contains(day(-365), now: now))
        #expect(AgendaDateWindow.all.contains(day(365), now: now))
    }
}
