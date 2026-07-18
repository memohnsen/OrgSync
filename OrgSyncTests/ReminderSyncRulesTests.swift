//
//  ReminderSyncRulesTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@Suite @MainActor struct ReminderSyncRulesTests {
    @Test func outboundDueDateUsesEarliestPlanningDateAndDropsTime() {
        let document = OrgParser.parse("""
        * TODO Both
        SCHEDULED: <2026-07-22 Wed 09:30> DEADLINE: <2026-07-20 Mon 17:00>
        """)
        let item = document.todoItems(filePath: "tasks.org")[0]

        let components = ReminderSyncRules.dueDateComponents(for: item)
        #expect(components?.year == 2026)
        #expect(components?.month == 7)
        #expect(components?.day == 20)
        #expect(components?.hour == nil)
        #expect(components?.minute == nil)
    }

    @Test func outboundDueDateSupportsScheduledOnlyDeadlineOnlyAndNoDate() {
        let scheduled = OrgParser.parse("* TODO Scheduled\nSCHEDULED: <2026-07-21 Tue>\n").todoItems(filePath: "a.org")[0]
        let deadline = OrgParser.parse("* TODO Deadline\nDEADLINE: <2026-07-22 Wed>\n").todoItems(filePath: "b.org")[0]
        let undated = OrgParser.parse("* TODO Undated\n").todoItems(filePath: "c.org")[0]

        #expect(ReminderSyncRules.dueDateComponents(for: scheduled)?.day == 21)
        #expect(ReminderSyncRules.dueDateComponents(for: deadline)?.day == 22)
        #expect(ReminderSyncRules.dueDateComponents(for: undated) == nil)
    }

    @Test func inboundDueDateUpdatesDeadlineOnlyTasksAndSchedulesAllOtherTasks() {
        let newDate = date(year: 2026, month: 8, day: 3)
        let cases: [(String, String, String)] = [
            ("* TODO Deadline\nDEADLINE: <2026-07-20 Mon>\n", "deadline", "scheduled"),
            ("* TODO Scheduled\nSCHEDULED: <2026-07-20 Mon>\n", "scheduled", "deadline"),
            ("* TODO Both\nSCHEDULED: <2026-07-20 Mon> DEADLINE: <2026-07-21 Tue>\n", "scheduled", "deadline"),
            ("* TODO Empty\n", "scheduled", "deadline"),
        ]

        for (text, expectedField, untouchedField) in cases {
            var headline = OrgParser.parse(text).headlines[0]
            ReminderSyncRules.applyIncomingDueDate(newDate, to: &headline)
            let changed = expectedField == "deadline" ? headline.planning.deadline : headline.planning.scheduled
            let untouched = untouchedField == "deadline" ? headline.planning.deadline : headline.planning.scheduled
            #expect(changed?.year == 2026 && changed?.month == 8 && changed?.day == 3, "\(expectedField) should change")
            if text.contains("Both") { #expect(untouched?.day == 21, "existing deadline must be preserved") }
        }
    }

    @Test func inboundDueDateIgnoresTimeOnlyChangesButAcceptsDifferentDays() {
        let item = OrgParser.parse("* TODO Timed\nSCHEDULED: <2026-07-20 Mon 09:00>\n")
            .todoItems(filePath: "timed.org")[0]
        #expect(!ReminderSyncRules.shouldApplyIncomingDueDate(date(year: 2026, month: 7, day: 20, hour: 18), to: item))
        #expect(ReminderSyncRules.shouldApplyIncomingDueDate(date(year: 2026, month: 7, day: 21), to: item))
    }

    @Test func priorityMappingCoversEverySupportedPriority() {
        #expect(ReminderSyncRules.priority(for: "A") == 1)
        #expect(ReminderSyncRules.priority(for: "B") == 5)
        #expect(ReminderSyncRules.priority(for: "C") == 9)
        #expect(ReminderSyncRules.priority(for: "D") == 0)
        #expect(ReminderSyncRules.priority(for: nil) == 0)
    }

    @Test func completingRecurringScheduledTaskAdvancesItsReminderDueDate() {
        var document = OrgParser.parse("* TODO Weekly\nSCHEDULED: <2026-07-01 Wed +1w>\n")
        let item = document.todoItems(filePath: "repeat.org")[0]
        ReminderSyncRules.complete(&document.headlines[0], item: item, document: document, now: date(year: 2026, month: 7, day: 18))

        #expect(document.headlines[0].todoKeyword == "TODO")
        #expect(document.headlines[0].planning.scheduled?.day == 8)
        #expect(document.headlines[0].planning.scheduled?.repeater?.text == "+1w")
        let refreshed = document.todoItems(filePath: "repeat.org")[0]
        #expect(ReminderSyncRules.dueDateComponents(for: refreshed)?.day == 8)
    }

    @Test func completingRecurringDeadlineTaskAdvancesWithoutMarkingItDone() {
        var document = OrgParser.parse("* TODO Daily\nDEADLINE: <2026-07-01 Wed +1d>\n")
        let item = document.todoItems(filePath: "repeat.org")[0]
        ReminderSyncRules.complete(&document.headlines[0], item: item, document: document, now: date(year: 2026, month: 7, day: 18))

        #expect(document.headlines[0].todoKeyword == "TODO")
        #expect(document.headlines[0].planning.deadline?.day == 2)
        #expect(document.headlines[0].planning.closed == nil)
    }

    @Test func completingNonRecurringTaskMarksItDoneAndAddsClosedTimestamp() {
        var document = OrgParser.parse("* TODO One shot\nSCHEDULED: <2026-07-20 Mon>\n")
        let item = document.todoItems(filePath: "one.org")[0]
        let now = date(year: 2026, month: 7, day: 18, hour: 10)
        ReminderSyncRules.complete(&document.headlines[0], item: item, document: document, now: now)

        #expect(document.headlines[0].todoKeyword == "DONE")
        #expect(document.headlines[0].planning.closed?.isActive == false)
        #expect(document.headlines[0].planning.closed?.day == 18)
    }

    @Test func completingTaskUsesDoneInsteadOfAnotherConfiguredCompletionState() {
        var document = OrgParser.parse("#+TODO: TODO | CANCELLED DONE\n* TODO Task\n")
        let item = document.todoItems(filePath: "tasks.org")[0]
        ReminderSyncRules.complete(&document.headlines[0], item: item, document: document,
                                   now: date(year: 2026, month: 7, day: 18))
        #expect(document.headlines[0].todoKeyword == "DONE")
        #expect(document.headlines[0].planning.closed != nil)
    }

    @Test func completingCatchUpRecurringTaskMovesPastToday() {
        var document = OrgParser.parse("* TODO Catch up\nSCHEDULED: <2026-07-01 Wed ++1w>\n")
        let item = document.todoItems(filePath: "catchup.org")[0]
        ReminderSyncRules.complete(&document.headlines[0], item: item, document: document, now: date(year: 2026, month: 7, day: 18))

        #expect(document.headlines[0].todoKeyword == "TODO")
        #expect(document.headlines[0].planning.scheduled?.day == 22)
        #expect(ReminderSyncRules.dueDateComponents(for: document.todoItems(filePath: "catchup.org")[0])?.day == 22)
    }

    @Test func inboxTimestampIsActiveDateOnly() {
        let timestamp = ReminderSyncRules.inboxScheduledTimestamp(for: date(year: 2026, month: 7, day: 30, hour: 16))
        #expect(timestamp.isActive)
        #expect(!timestamp.hasTime)
        #expect(timestamp.serialize() == "<2026-07-30 Thu>")
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = OrgTimestamp.calendar
        components.year = year; components.month = month; components.day = day; components.hour = hour
        return OrgTimestamp.calendar.date(from: components)!
    }
}
