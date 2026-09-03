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

    @Test func renderIncludesPersistentIDPropertyDrawer() {
        let text = CalendarSyncRules.render(events: [
            .init(persistentID: "ABC-123", title: "Meet", start: date(2026, 7, 22, 10, 0), isAllDay: false),
        ])
        #expect(text.contains(":ID: ABC-123"))
        #expect(text.contains("* TODO Meet\n:PROPERTIES:"))
    }

    @Test func eventsFromDocumentParsesScheduledTodosWithIDs() {
        let document = OrgParser.parse("""
        * TODO Standup
        :PROPERTIES:
        :ID: STANDUP-ID
        :END:
        SCHEDULED: <2026-07-22 Wed 09:00>
        """)
        let events = CalendarSyncRules.events(from: document)
        #expect(events.count == 1)
        #expect(events[0].persistentID == "STANDUP-ID")
        #expect(events[0].title == "Standup")
        #expect(events[0].isAllDay == false)
    }

    @Test func eventsInWindowFiltersOutsideWindow() {
        let now = date(2026, 7, 20, 12, 0)
        let document = OrgParser.parse("""
        * TODO Inside
        SCHEDULED: <2026-07-21 Tue>
        * TODO Outside
        SCHEDULED: <2026-09-01 Mon>
        """)
        let events = CalendarSyncRules.events(inWindowFrom: document, now: now)
        #expect(events.map(\.title) == ["Inside"])
    }

    @Test func orgMasterRenderUsesManagedHeader() {
        let text = CalendarSyncRules.render(events: [], orgIsMaster: true)
        #expect(text.contains("Managed by OrgSync"))
        #expect(!text.contains("Read-only mirror"))
    }

    @Test func mappingKeyUsesPersistentIDPrefix() {
        #expect(CalendarSyncRules.mappingKey(persistentID: "ABC") == "id|ABC")
    }

    @Test func footerWindowMatchesSyncWindowConstant() {
        #expect(CalendarSyncRules.windowDays == 30)
    }

    @Test func exportUpsertPlansKeepExistingEventsOnTheirCalendar() {
        let events = [
            CalendarSyncRules.Event(persistentID: "ORG-1", title: "Existing", start: date(2026, 7, 22), isAllDay: true),
            CalendarSyncRules.Event(persistentID: "ORG-2", title: "New", start: date(2026, 7, 23), isAllDay: true),
        ]
        let mappings = ["ORG-1": "EVT-1", "ORG-2": "EVT-MISSING"]
        let plans = CalendarSyncRules.exportUpsertPlans(
            orgEvents: events,
            mappings: mappings,
            existingMappedEventIDs: ["EVT-1"]
        )
        #expect(plans == [
            .init(orgID: "ORG-1", usesManagedCalendar: false),
            .init(orgID: "ORG-2", usesManagedCalendar: true),
        ])
    }

    @Test func staleMappedOrgIDsOnlyIncludeMissingLiveEntries() {
        let stale = CalendarSyncRules.staleMappedOrgIDs(
            seenOrgIDs: ["KEEP"],
            mappings: ["KEEP": "EVT-1", "GONE": "EVT-2"]
        )
        #expect(stale == ["GONE"])
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
