//
//  AutoSyncAndWorkerTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct AutoSyncPolicyTests {
    @Test func activeLifecycleCoversEverySettingsCombination() {
        for autoSync in [false, true] {
            for connected in [false, true] {
                for pullOnOpen in [false, true] {
                    for pushOnClose in [false, true] {
                        for reminders in [false, true] {
                            let actions = AutoSyncPolicy.actions(
                                for: .active,
                                autoSyncEnabled: autoSync,
                                isConnected: connected,
                                pullOnOpen: pullOnOpen,
                                pushOnClose: pushOnClose,
                                remindersSyncEnabled: reminders
                            )
                            let expected: [AutoSyncAction]
                            if autoSync && connected && pullOnOpen {
                                expected = reminders ? [.pullThenSyncReminders] : [.pull]
                            } else {
                                expected = reminders ? [.syncReminders] : []
                            }
                            #expect(actions == expected, "active: auto=\(autoSync), connected=\(connected), pull=\(pullOnOpen), push=\(pushOnClose), reminders=\(reminders)")
                        }
                    }
                }
            }
        }
    }

    @Test func backgroundLifecycleCoversEverySettingsCombination() {
        for autoSync in [false, true] {
            for connected in [false, true] {
                for pullOnOpen in [false, true] {
                    for pushOnClose in [false, true] {
                        for reminders in [false, true] {
                            let actions = AutoSyncPolicy.actions(
                                for: .background,
                                autoSyncEnabled: autoSync,
                                isConnected: connected,
                                pullOnOpen: pullOnOpen,
                                pushOnClose: pushOnClose,
                                remindersSyncEnabled: reminders
                            )
                            let expected: [AutoSyncAction] = autoSync && connected && pushOnClose ? [.push] : []
                            #expect(actions == expected, "background: auto=\(autoSync), connected=\(connected), pull=\(pullOnOpen), push=\(pushOnClose), reminders=\(reminders)")
                        }
                    }
                }
            }
        }
    }

    @Test func inactiveLifecycleNeverSchedulesWork() {
        #expect(AutoSyncPolicy.actions(
            for: .inactive,
            autoSyncEnabled: true,
            isConnected: true,
            pullOnOpen: true,
            pushOnClose: true,
            remindersSyncEnabled: true
        ).isEmpty)
    }
}

@Suite struct SyncWorkerLocalStatusTests {
    @Test func classifiesModifiedAddedDeletedAndSkippedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let unchanged = Data("unchanged".utf8)
        let original = Data("original".utf8)
        try unchanged.write(to: root.appendingPathComponent("unchanged.org"))
        try Data("changed".utf8).write(to: root.appendingPathComponent("modified.org"))
        try Data("new".utf8).write(to: root.appendingPathComponent("added.org"))
        try Data("ignored local edit".utf8).write(to: root.appendingPathComponent("large.pdf"))
        let metadataDirectory = root.appendingPathComponent(".orgsync", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try Data("metadata".utf8).write(to: metadataDirectory.appendingPathComponent("state.json"), options: .atomic)

        let state = SyncRepoState(
            owner: "owner",
            repo: "repo",
            branch: "main",
            baseCommitSHA: "base",
            files: [
                "unchanged.org": GitBlob.sha1(for: unchanged),
                "modified.org": GitBlob.sha1(for: original),
                "deleted.org": GitBlob.sha1(for: Data("deleted".utf8)),
                "large.pdf": GitBlob.sha1(for: Data("remote large blob".utf8)),
            ],
            skippedPaths: ["large.pdf"]
        )

        let status = await SyncWorker(repoURL: root).localStatus(state: state)
        #expect(status.modified == ["modified.org"])
        #expect(status.added == ["added.org"])
        #expect(status.deleted == ["deleted.org"])
        #expect(status.localChangeCount == 3)
    }

    @Test func stagingAllChangesPersistsEveryChangedPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = Data("before".utf8)
        try Data("after".utf8).write(to: root.appendingPathComponent("changed.org"))
        try Data("new".utf8).write(to: root.appendingPathComponent("new.org"))
        let state = SyncRepoState(
            owner: "owner", repo: "repo", branch: "main", baseCommitSHA: "base",
            files: ["changed.org": GitBlob.sha1(for: original), "deleted.org": GitBlob.sha1(for: Data("gone".utf8))]
        )

        let result = await SyncWorker(repoURL: root).stageAll(state: state)
        #expect(result.state.stagedPaths == ["changed.org", "deleted.org", "new.org"])
        #expect(result.status.localChangeCount == 3)
    }
}

@Suite @MainActor struct SyncSettingsPersistenceTests {
    @Test func syncPreferencesSurviveStoreRecreation() {
        let suiteName = "OrgSyncTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.repoURL = "owner/repository"
        settings.branch = "release"
        settings.autoSync = true
        settings.pullOnOpen = true
        settings.pushOnClose = true

        let restored = SettingsStore(defaults: defaults)
        #expect(restored.repoURL == "owner/repository")
        #expect(restored.branch == "release")
        #expect(restored.autoSync)
        #expect(restored.pullOnOpen)
        #expect(restored.pushOnClose)
        #expect(restored.todoKeywords == OrgTodoConfig.defaultPreference)
        #expect(restored.todoStatusColors.isEmpty)
    }
}
