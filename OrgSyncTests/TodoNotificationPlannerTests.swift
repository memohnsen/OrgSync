//
//  TodoNotificationPlannerTests.swift
//  OrgSyncTests
//
//  Verifies the pure notification planning logic: which TODOs notify, when,
//  per-offset fan-out for timed TODOs, the all-day time-of-day setting, past
//  and done filtering, ordering, capping, and settings persistence.
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct TodoNotificationPlannerTests {
    private func todo(
        title: String,
        file: String = "inbox.org",
        keyword: String = "TODO",
        isDone: Bool = false,
        scheduled: OrgTimestamp? = nil,
        deadline: OrgTimestamp? = nil
    ) -> OrgTodoItem {
        OrgTodoItem(
            outline: OrgOutline(filePath: file, headingPath: [title], index: 0),
            keyword: keyword, isDone: isDone, priority: nil,
            title: title, tags: [], scheduled: scheduled, deadline: deadline)
    }

    private func timestamp(_ y: Int, _ m: Int, _ d: Int, _ hour: Int? = nil, _ minute: Int? = nil) -> OrgTimestamp {
        OrgTimestamp(isActive: true, year: y, month: m, day: d, startHour: hour, startMinute: minute)
    }

    /// A fixed "now": 2026-07-20 08:00 in the org calendar's timezone.
    private var now: Date { timestamp(2026, 7, 20, 8, 0).date()! }

    @Test func timedTodoFiresOncePerOffset() {
        let item = todo(title: "Standup", scheduled: timestamp(2026, 7, 20, 10, 0))
        let plan = TodoNotificationPlanner.plan(
            todos: [item], allDayMinutes: nil, timedOffsetsMinutes: [0, 15, 60], now: now)

        #expect(plan.count == 3)
        let event = timestamp(2026, 7, 20, 10, 0).date()!
        #expect(Set(plan.map(\.fireDate)) == [
            event, event.addingTimeInterval(-15 * 60), event.addingTimeInterval(-60 * 60)
        ])
        // Soonest-first ordering.
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
    }

    @Test func allDayTodoFiresAtConfiguredTime() {
        let item = todo(title: "Pay rent", deadline: timestamp(2026, 7, 21))
        let plan = TodoNotificationPlanner.plan(
            todos: [item], allDayMinutes: 9 * 60, timedOffsetsMinutes: [0], now: now)

        #expect(plan.count == 1)
        #expect(plan.first?.fireDate == timestamp(2026, 7, 21, 9, 0).date())
        #expect(plan.first?.body.contains("Deadline") == true)
    }

    @Test func allDayTodoSkippedWhenAllDayNotificationsAreOff() {
        let item = todo(title: "Pay rent", scheduled: timestamp(2026, 7, 21))
        let plan = TodoNotificationPlanner.plan(
            todos: [item], allDayMinutes: nil, timedOffsetsMinutes: [0], now: now)
        #expect(plan.isEmpty)
    }

    @Test func doneUndatedAndPastTodosAreSkipped() {
        let items = [
            todo(title: "Done", isDone: true, scheduled: timestamp(2026, 7, 20, 10, 0)),
            todo(title: "Undated"),
            todo(title: "Past", scheduled: timestamp(2026, 7, 20, 7, 0)),
            todo(title: "Future", scheduled: timestamp(2026, 7, 20, 12, 0)),
        ]
        let plan = TodoNotificationPlanner.plan(
            todos: items, allDayMinutes: 9 * 60, timedOffsetsMinutes: [0], now: now)
        #expect(plan.map(\.title) == ["Future"])
    }

    @Test func offsetInThePastIsDroppedButFutureOffsetsKept() {
        // Event at 8:30; a 60-min lead time would be 7:30 (before now) and is
        // dropped, while the at-event notification is kept.
        let item = todo(title: "Soon", scheduled: timestamp(2026, 7, 20, 8, 30))
        let plan = TodoNotificationPlanner.plan(
            todos: [item], allDayMinutes: nil, timedOffsetsMinutes: [0, 60], now: now)
        #expect(plan.count == 1)
        #expect(plan.first?.fireDate == timestamp(2026, 7, 20, 8, 30).date())
    }

    @Test func scheduledWinsOverDeadlineAndDuplicateOffsetsCollapse() {
        let item = todo(title: "Both",
                        scheduled: timestamp(2026, 7, 20, 10, 0),
                        deadline: timestamp(2026, 7, 22, 10, 0))
        let plan = TodoNotificationPlanner.plan(
            todos: [item], allDayMinutes: nil, timedOffsetsMinutes: [5, 5], now: now)
        #expect(plan.count == 1)
        #expect(plan.first?.fireDate == timestamp(2026, 7, 20, 9, 55).date())
        #expect(plan.first?.body.contains("Scheduled") == true)
    }

    @Test func planIsCappedAtTheSystemLimit() {
        let items = (0..<100).map {
            todo(title: "Task \($0)",
                 scheduled: timestamp(2026, 7, 21, 9, $0 % 60))
        }
        let plan = TodoNotificationPlanner.plan(
            todos: items, allDayMinutes: nil, timedOffsetsMinutes: [0], now: now)
        #expect(plan.count == TodoNotificationPlanner.maxPlanned)
    }

    @Test func identifiersAreStableAndPrefixed() {
        let item = todo(title: "Standup", scheduled: timestamp(2026, 7, 20, 10, 0))
        let plan1 = TodoNotificationPlanner.plan(todos: [item], allDayMinutes: nil, timedOffsetsMinutes: [5], now: now)
        let plan2 = TodoNotificationPlanner.plan(todos: [item], allDayMinutes: nil, timedOffsetsMinutes: [5], now: now)
        #expect(plan1.first?.id == plan2.first?.id)
        #expect(plan1.first?.id.hasPrefix(TodoNotificationPlanner.identifierPrefix) == true)
    }

    @Test func offsetLabelsUseMinutesAndHours() {
        #expect(TodoNotificationPlanner.offsetLabel(5) == "5 min")
        #expect(TodoNotificationPlanner.offsetLabel(90) == "90 min")
        #expect(TodoNotificationPlanner.offsetLabel(60) == "1 hr")
        #expect(TodoNotificationPlanner.offsetLabel(120) == "2 hr")
    }
}

@Suite struct NotificationSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "notification-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsAreOffNineAMAndAtEventTime() {
        let settings = SettingsStore(defaults: makeDefaults())
        #expect(settings.todoNotifications == false)
        #expect(settings.allDayNotificationMinutes == 9 * 60)
        #expect(settings.timedNotificationOffsets == [0])
    }

    @Test func valuesRoundTripThroughUserDefaults() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.todoNotifications = true
        settings.allDayNotificationMinutes = 8 * 60 + 30
        settings.timedNotificationOffsets = [0, 15, 45]

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.todoNotifications == true)
        #expect(reloaded.allDayNotificationMinutes == 8 * 60 + 30)
        #expect(reloaded.timedNotificationOffsets == [0, 15, 45])
    }

    @Test func allDayOffPersistsAsOff() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.allDayNotificationMinutes = nil
        #expect(SettingsStore(defaults: defaults).allDayNotificationMinutes == nil)
    }
}
