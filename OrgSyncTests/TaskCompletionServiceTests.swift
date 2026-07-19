//
//  TaskCompletionServiceTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@MainActor
@Suite struct TaskCompletionServiceTests {
    @Test func archivesCompletedOneOffInboxTaskWhenEnabled() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("inbox.org")
        try "* TODO File taxes\n* TODO Keep\n".write(to: inbox, atomically: true, encoding: .utf8)
        repo.refresh()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        settings.archiveCompletedInboxTasks = true
        let task = try #require(repo.allTodoItems().first { $0.title == "File taxes" })

        #expect(TaskCompletionService.complete(task, repo: repo, settings: settings))

        let inboxText = try String(contentsOf: inbox, encoding: .utf8)
        let doneText = try String(contentsOf: root.appendingPathComponent("done.org"), encoding: .utf8)
        #expect(!inboxText.contains("File taxes"))
        #expect(inboxText.contains("TODO Keep"))
        #expect(doneText.contains("DONE File taxes"))
    }

    @Test func leavesInboxTaskInPlaceWhenArchivingDisabled() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("inbox.org")
        try "* TODO Keep here\n".write(to: inbox, atomically: true, encoding: .utf8)
        repo.refresh()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        let task = try #require(repo.allTodoItems().first)

        #expect(TaskCompletionService.complete(task, repo: repo, settings: settings))
        #expect((try String(contentsOf: inbox, encoding: .utf8)).contains("DONE Keep here"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("done.org").path))
    }

    @Test func recurringInboxTaskAdvancesAndIsNeverArchived() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("inbox.org")
        try "* TODO Weekly\nSCHEDULED: <2026-07-01 Wed +1w>\n".write(to: inbox, atomically: true, encoding: .utf8)
        repo.refresh()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        settings.archiveCompletedInboxTasks = true
        let task = try #require(repo.allTodoItems().first)

        #expect(TaskCompletionService.complete(task, repo: repo, settings: settings))
        let text = try String(contentsOf: inbox, encoding: .utf8)
        #expect(text.contains("TODO Weekly"))
        #expect(text.contains("+1w"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("done.org").path))
    }

    private func makeRepo() throws -> (RepoStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (RepoStore(repoURL: root, seedsSampleContent: false), root)
    }
}
