//
//  WidgetCompletionReconcilerTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@MainActor
@Suite struct WidgetCompletionReconcilerTests {
    private func makeRepo() throws -> (RepoStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = RepoStore(repoURL: root, seedsSampleContent: false)
        return (repo, root)
    }

    @Test func queuedCompletionMarksTheNoteDoneAndClearsQueue() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("tasks.org")
        try "* TODO Ship it\nSCHEDULED: <2026-07-20 Mon>\n* TODO Keep me\nSCHEDULED: <2026-07-21 Tue>\n"
            .write(to: file, atomically: true, encoding: .utf8)
        repo.refresh()

        let target = try #require(repo.allTodoItems().first { $0.title == "Ship it" })
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        defaults.set([AgendaSnapshotWriter.snapshotID(for: target)], forKey: AgendaSnapshot.pendingCompletionsKey)

        WidgetCompletionReconciler.reconcile(repo: repo, defaults: defaults)

        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(after.contains("DONE Ship it"), "the queued TODO should be marked DONE")
        #expect(after.contains("TODO Keep me"), "an unqueued TODO must be left untouched")
        #expect(defaults.stringArray(forKey: AgendaSnapshot.pendingCompletionsKey) == nil,
                "the completion queue should be drained")
    }

    @Test func emptyQueueIsANoOp() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("tasks.org")
        try "* TODO Ship it\nSCHEDULED: <2026-07-20 Mon>\n".write(to: file, atomically: true, encoding: .utf8)
        repo.refresh()

        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        WidgetCompletionReconciler.reconcile(repo: repo, defaults: defaults)

        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(after.contains("TODO Ship it"))
    }

    @Test func staleQueuedIDIsDiscardedNotReapplied() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("tasks.org")
        try "* TODO Ship it\nSCHEDULED: <2026-07-20 Mon>\n".write(to: file, atomically: true, encoding: .utf8)
        repo.refresh()

        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        defaults.set(["does/not/exist.org|Ghost|0"], forKey: AgendaSnapshot.pendingCompletionsKey)
        WidgetCompletionReconciler.reconcile(repo: repo, defaults: defaults)

        #expect(defaults.stringArray(forKey: AgendaSnapshot.pendingCompletionsKey) == nil)
        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(after.contains("TODO Ship it"))
    }
}
