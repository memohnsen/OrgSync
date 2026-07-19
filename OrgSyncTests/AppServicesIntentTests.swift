//
//  AppServicesIntentTests.swift
//  OrgSyncTests
//
//  Covers the shared bridge behind the App Intents: capture, complete, and
//  range queries against a registered test repo.
//

import Foundation
import Testing
@testable import OrgSync

@MainActor
@Suite(.serialized) struct AppServicesIntentTests {
    private func makeRepo() -> (RepoStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = RepoStore(repoURL: root, seedsSampleContent: false)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        AppServices.register(repo: repo, settings: settings, sync: SyncEngine(repo: repo, settings: settings))
        return (repo, root)
    }

    private func line(_ title: String, _ date: Date) -> String {
        "* TODO \(title)\nSCHEDULED: \(OrgTimestamp(date: date, isActive: true, includeTime: false).serialize())\n"
    }

    @Test func captureAppendsTodoToInbox() throws {
        let (_, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(AppServices.capture("Buy milk", scheduled: nil))
        let inbox = try String(contentsOf: root.appendingPathComponent("inbox.org"), encoding: .utf8)
        #expect(inbox.contains("* TODO Buy milk"))
        #expect(!inbox.contains("SCHEDULED:"))
    }

    @Test func captureWithDateAddsSchedule() throws {
        let (_, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(AppServices.capture("Call dentist", scheduled: .now))
        let inbox = try String(contentsOf: root.appendingPathComponent("inbox.org"), encoding: .utf8)
        #expect(inbox.contains("* TODO Call dentist"))
        #expect(inbox.contains("SCHEDULED:"))
    }

    @Test func completeTaskMarksItDone() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try line("Ship it", .now).write(to: root.appendingPathComponent("tasks.org"), atomically: true, encoding: .utf8)
        repo.refresh()

        let item = try #require(AppServices.openTasks().first { $0.title == "Ship it" })
        #expect(AppServices.completeTask(id: AgendaSnapshotWriter.snapshotID(for: item)))

        let after = try String(contentsOf: root.appendingPathComponent("tasks.org"), encoding: .utf8)
        #expect(after.contains("DONE Ship it"))
        #expect(AppServices.openTasks().contains { $0.title == "Ship it" } == false)
    }

    @Test func rangeQueriesWindowByDate() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let inThree = calendar.date(byAdding: .day, value: 3, to: today)!
        let inThirty = calendar.date(byAdding: .day, value: 30, to: today)!
        let body = line("Today task", today) + line("Week task", inThree) + line("Far task", inThirty)
        try body.write(to: root.appendingPathComponent("tasks.org"), atomically: true, encoding: .utf8)
        repo.refresh()

        #expect(AppServices.tasks(in: .today).map(\.title) == ["Today task"])
        #expect(AppServices.tasks(in: .week).map(\.title) == ["Today task", "Week task"])
        #expect(AppServices.tasks(in: .upcoming).map(\.title) == ["Today task", "Week task", "Far task"])
    }
}
