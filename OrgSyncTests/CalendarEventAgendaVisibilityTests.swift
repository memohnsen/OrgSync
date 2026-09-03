//
//  CalendarEventAgendaVisibilityTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct CalendarEventAgendaVisibilityTests {
    private let calendar = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func snapshotItem(
        title: String,
        filePath: String,
        scheduled: Date?
    ) -> AgendaSnapshotItem {
        AgendaSnapshotItem(
            id: title,
            title: title,
            filePath: filePath,
            scheduled: scheduled,
            deadline: nil,
            priority: nil,
            tags: []
        )
    }

    private func snapshot(from item: OrgTodoItem) -> AgendaSnapshotItem {
        snapshotItem(
            title: item.title,
            filePath: item.outline.filePath,
            scheduled: item.scheduled?.date()
        )
    }

    @Test func timedCalendarEventStillVisibleTwentyNineMinutesAfterStart() {
        let start = date(2026, 7, 22, 9, 0)
        let now = start.addingTimeInterval(29 * 60)
        #expect(CalendarEventAgendaVisibility.isVisible(
            isCalendarEvent: true,
            scheduled: start,
            now: now
        ))
        #expect(snapshotItem(title: "Standup", filePath: CalendarSyncRules.fileName, scheduled: start)
            .isVisibleOnAgenda(now: now))
    }

    @Test func timedCalendarEventHiddenAtThirtyMinutesAfterStart() {
        let start = date(2026, 7, 22, 9, 0)
        let now = start.addingTimeInterval(30 * 60)
        #expect(!CalendarEventAgendaVisibility.isVisible(
            isCalendarEvent: true,
            scheduled: start,
            now: now
        ))
        #expect(!snapshotItem(title: "Standup", filePath: CalendarSyncRules.fileName, scheduled: start)
            .isVisibleOnAgenda(now: now))
    }

    @Test func allDayCalendarEventRemainsAfterStart() {
        let start = date(2026, 7, 22)
        let now = date(2026, 7, 22, 16, 0)
        #expect(CalendarEventAgendaVisibility.isVisible(
            isCalendarEvent: true,
            scheduled: start,
            now: now
        ))
        #expect(snapshotItem(title: "Holiday", filePath: CalendarSyncRules.fileName, scheduled: start)
            .isVisibleOnAgenda(now: now))
    }

    @Test func regularTodoWithScheduledTimeIsNotHidden() {
        let start = date(2026, 7, 22, 9, 0)
        let now = start.addingTimeInterval(8 * 60 * 60)
        #expect(CalendarEventAgendaVisibility.isVisible(
            isCalendarEvent: false,
            scheduled: start,
            now: now
        ))
        #expect(snapshotItem(title: "Call Sam", filePath: "inbox.org", scheduled: start)
            .isVisibleOnAgenda(now: now))
    }

    @Test func widgetAndAgendaShareTheSameDecision() {
        let start = date(2026, 7, 22, 9, 0)
        let now = start.addingTimeInterval(30 * 60)
        let orgItems = OrgParser.parse(CalendarSyncRules.render(events: [
            .init(title: "Standup", start: start, isAllDay: false),
            .init(title: "Holiday", start: date(2026, 7, 22), isAllDay: true),
        ])).todoItems(filePath: CalendarSyncRules.fileName)
            + OrgParser.parse("""
            * TODO Call Sam
            SCHEDULED: <2026-07-22 Wed 09:00>
            """).todoItems(filePath: "inbox.org")

        let agendaVisible = orgItems.filter {
            CalendarEventAgendaVisibility.isVisible(
                isCalendarEvent: $0.outline.filePath == CalendarSyncRules.fileName,
                scheduled: $0.scheduled?.date(),
                now: now
            )
        }.map(\.title).sorted()

        let widgetVisible = orgItems.map(snapshot(from:)).filter {
            $0.isVisibleOnAgenda(now: now)
        }.map(\.title).sorted()

        #expect(agendaVisible == widgetVisible)
        #expect(agendaVisible == ["Call Sam", "Holiday"])
    }

    @Test func nextReloadUsesStartPlusThirtyWhenSoonerThanFallback() {
        let start = date(2026, 7, 22, 9, 0)
        let now = start.addingTimeInterval(20 * 60)
        let fallback = now.addingTimeInterval(15 * 60)
        let items = [
            snapshotItem(title: "Standup", filePath: CalendarSyncRules.fileName, scheduled: start),
        ]
        #expect(
            CalendarEventAgendaVisibility.nextReloadDate(from: items, now: now, fallback: fallback)
            == start.addingTimeInterval(30 * 60)
        )
    }

    @Test func nextReloadKeepsFallbackForAllDayAndOrdinaryTodos() {
        let start = date(2026, 7, 22, 9, 0)
        let now = start.addingTimeInterval(20 * 60)
        let fallback = now.addingTimeInterval(15 * 60)
        let items = [
            snapshotItem(title: "Holiday", filePath: CalendarSyncRules.fileName, scheduled: date(2026, 7, 22)),
            snapshotItem(title: "Call Sam", filePath: "inbox.org", scheduled: start),
        ]
        #expect(
            CalendarEventAgendaVisibility.nextReloadDate(from: items, now: now, fallback: fallback)
            == fallback
        )
    }
}

@MainActor
@Suite(.serialized) struct CalendarEventAgendaSnapshotTests {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func agendaItemsHideStartedCalendarEventsAndKeepTodos() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = RepoStore(repoURL: root, seedsSampleContent: false)
        let start = date(2026, 7, 22, 9, 0)
        try "* TODO Call Sam\nSCHEDULED: <2026-07-22 Wed 09:00>\n"
            .write(to: root.appendingPathComponent("inbox.org"), atomically: true, encoding: .utf8)
        try CalendarSyncRules.render(events: [
            .init(title: "Standup", start: start, isAllDay: false),
            .init(title: "Holiday", start: date(2026, 7, 22), isAllDay: true),
        ]).write(to: root.appendingPathComponent(CalendarSyncRules.fileName), atomically: true, encoding: .utf8)
        repo.refresh()

        let stillVisible = AgendaSnapshotWriter.agendaItems(
            repo: repo,
            now: start.addingTimeInterval(29 * 60)
        ).map(\.title).sorted()
        #expect(stillVisible == ["Call Sam", "Holiday", "Standup"])

        let hidden = AgendaSnapshotWriter.agendaItems(
            repo: repo,
            now: start.addingTimeInterval(30 * 60)
        ).map(\.title).sorted()
        #expect(hidden == ["Call Sam", "Holiday"])
    }
}
