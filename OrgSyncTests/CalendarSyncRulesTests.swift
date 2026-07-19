//
//  CalendarSyncRulesTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct CalendarSyncRulesTests {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func rendersEventsSortedWithTimesAndAllDay() {
        let text = CalendarSyncRules.render(events: [
            .init(title: "Dentist", start: date(2026, 7, 22, 14, 30), isAllDay: false),
            .init(title: "Company Holiday", start: date(2026, 7, 21), isAllDay: true),
        ])
        #expect(text.hasPrefix("#+TITLE: Calendar\n"))
        #expect(text.contains("* TODO Company Holiday\nSCHEDULED: <2026-07-21 Tue>\n"))
        #expect(text.contains("* TODO Dentist\nSCHEDULED: <2026-07-22 Wed 14:30>\n"))
        // Sorted by start: the holiday (earlier) comes first.
        let holiday = text.range(of: "Company Holiday")!.lowerBound
        let dentist = text.range(of: "Dentist")!.lowerBound
        #expect(holiday < dentist)
    }

    @Test func identicalStartsSortByTitleAndEmptyTitlesAreSkipped() {
        let start = date(2026, 7, 23, 9, 0)
        let text = CalendarSyncRules.render(events: [
            .init(title: "Zeta", start: start, isAllDay: false),
            .init(title: "Alpha", start: start, isAllDay: false),
            .init(title: "   ", start: start, isAllDay: false),
        ])
        #expect(text.range(of: "Alpha")!.lowerBound < text.range(of: "Zeta")!.lowerBound)
        #expect(!text.contains("* TODO  \n"))
    }

    @Test func renderIsStableForRegeneration() {
        let events: [CalendarSyncRules.Event] = [
            .init(title: "B", start: date(2026, 7, 24, 10, 0), isAllDay: false),
            .init(title: "A", start: date(2026, 7, 24, 8, 0), isAllDay: false),
        ]
        #expect(CalendarSyncRules.render(events: events) == CalendarSyncRules.render(events: events.reversed()))
    }

    @Test func windowSpansThirtyDaysFromMidnight() {
        let now = date(2026, 7, 20, 15, 45)
        let window = CalendarSyncRules.window(now: now)
        #expect(window.start == Calendar.current.startOfDay(for: now))
        #expect(window.end == date(2026, 8, 19))
    }
}

@MainActor
@Suite(.serialized) struct CalendarAgendaVisibilityTests {
    @Test func hiddenCalendarEventsAreExcludedFromAgendaItems() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = RepoStore(repoURL: root, seedsSampleContent: false)
        try "* TODO Real task\nSCHEDULED: <2026-07-21 Tue>\n"
            .write(to: root.appendingPathComponent("inbox.org"), atomically: true, encoding: .utf8)
        try CalendarSyncRules.render(events: [
            .init(title: "Standup", start: .now, isAllDay: false),
        ]).write(to: root.appendingPathComponent(CalendarSyncRules.fileName), atomically: true, encoding: .utf8)
        repo.refresh()

        let key = SettingsStore.calendarShowInAgendaKey
        let original = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }

        UserDefaults.standard.set(true, forKey: key)
        #expect(Set(AgendaSnapshotWriter.agendaItems(repo: repo).map(\.title)) == ["Real task", "Standup"])

        UserDefaults.standard.set(false, forKey: key)
        #expect(AgendaSnapshotWriter.agendaItems(repo: repo).map(\.title) == ["Real task"])
    }
}
