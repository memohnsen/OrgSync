//
//  WidgetAgendaRowTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct WidgetAgendaRowTests {
    private func calendarUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: hour, minute: minute))!
    }

    private func item(
        title: String = "Standup",
        filePath: String,
        scheduled: Date? = nil,
        tags: [String] = []
    ) -> AgendaSnapshotItem {
        AgendaSnapshotItem(
            id: "id",
            title: title,
            filePath: filePath,
            scheduled: scheduled,
            deadline: nil,
            priority: nil,
            tags: tags
        )
    }

    @Test func calendarOrgFilePathIsTheEventSignal() {
        let event = item(filePath: CalendarSyncRules.fileName)
        let todo = item(filePath: "inbox.org")
        #expect(event.isCalendarEvent)
        #expect(!todo.isCalendarEvent)
        #expect(!event.showsWidgetCompleteControl)
        #expect(todo.showsWidgetCompleteControl)
    }

    @Test func calendarEventShowsStartTimeInsteadOfTags() {
        let calendar = calendarUTC()
        let start = date(14, 30, calendar: calendar)
        let event = item(
            filePath: CalendarSyncRules.fileName,
            scheduled: start,
            tags: ["TODO"]
        )
        let meta = event.widgetTrailingMeta(
            allDayText: "All day",
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )
        #expect(!event.showsWidgetCompleteControl)
        #expect(meta != "#TODO")
        #expect(meta?.contains("2:30") == true || meta?.contains("14:30") == true)
    }

    @Test func allDayCalendarEventShowsAllDay() {
        let calendar = calendarUTC()
        let event = item(filePath: CalendarSyncRules.fileName, scheduled: date(0, 0, calendar: calendar))
        #expect(event.widgetTrailingMeta(allDayText: "All day", calendar: calendar) == "All day")
    }

    @Test func normalTodoKeepsCompleteControlAndTags() {
        let todo = item(filePath: "tasks.org", tags: ["work", "home"])
        #expect(todo.showsWidgetCompleteControl)
        #expect(todo.widgetTrailingMeta(allDayText: "All day") == "#work #home")
    }

    @Test func trailingMetaDoesNotDependOnTitleLength() {
        let calendar = calendarUTC()
        let start = date(9, 5, calendar: calendar)
        let short = item(title: "A", filePath: CalendarSyncRules.fileName, scheduled: start)
        let long = item(
            title: String(repeating: "Meeting", count: 40),
            filePath: CalendarSyncRules.fileName,
            scheduled: start
        )
        #expect(
            short.widgetTrailingMeta(allDayText: "All day", calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
            == long.widgetTrailingMeta(allDayText: "All day", calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
        )
    }

    @Test func calendarOrgHeadlinesDriveEventRows() {
        let timed = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 14, minute: 30))!
        let allDay = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 21))!
        let items = OrgParser.parse(CalendarSyncRules.render(events: [
            .init(title: "Dentist", start: timed, isAllDay: false),
            .init(title: "Holiday", start: allDay, isAllDay: true),
        ])).todoItems(filePath: CalendarSyncRules.fileName)

        func snapshot(_ todo: OrgTodoItem) -> AgendaSnapshotItem {
            AgendaSnapshotItem(
                id: "id",
                title: todo.title,
                filePath: todo.outline.filePath,
                scheduled: todo.scheduled?.date(),
                deadline: todo.deadline?.date(),
                priority: todo.priority.map(String.init),
                tags: todo.tags
            )
        }

        let dentist = snapshot(try #require(items.first { $0.title == "Dentist" }))
        let holiday = snapshot(try #require(items.first { $0.title == "Holiday" }))
        #expect(dentist.isCalendarEvent)
        #expect(!dentist.showsWidgetCompleteControl)
        let dentistTime = dentist.widgetTrailingMeta(allDayText: "All day")
        #expect(dentistTime != "All day")
        #expect(dentistTime?.contains("2:30") == true || dentistTime?.contains("14:30") == true)
        #expect(holiday.widgetTrailingMeta(allDayText: "All day") == "All day")
        #expect(!holiday.showsWidgetCompleteControl)
    }
}
