//
//  SyncEngineConcurrencyTests.swift
//  OrgSyncTests
//
//  Exercises SyncEngine end-to-end against the fake GitHub API to confirm
//  overlapping operations are serialized rather than acting on stale state.
//

import Foundation
import Testing
@testable import OrgSync

@MainActor
@Suite(.serialized) struct SyncEngineConcurrencyTests {
    private func connectedEngine(remote: FakeGitHubRepo) async throws -> (SyncEngine, RepoStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = RepoStore(repoURL: root, seedsSampleContent: false)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        settings.repoURL = "\(remote.owner)/\(remote.repo)"
        settings.branch = "main"
        settings.token = "test-token"
        let engine = SyncEngine(repo: repo, settings: settings, session: remote.makeSession())
        try await engine.connect(branch: "main")
        return (engine, repo, root)
    }

    @Test func overlappingSyncsProduceExactlyOneCommit() async throws {
        let remote = FakeGitHubRepo()
        remote.seedCommit(branch: "main", changes: ["a.org": Data("v1\n".utf8)])
        let (engine, repo, root) = try await connectedEngine(remote: remote)
        defer { try? FileManager.default.removeItem(at: root) }

        let commitsBefore = remote.commitCount
        try "* TODO edited\n".write(to: root.appendingPathComponent("a.org"), atomically: true, encoding: .utf8)
        repo.refresh()

        // Fire two syncs concurrently; serialization must let only the first
        // push, with the second seeing a clean tree.
        async let first: Void = engine.syncNow()
        async let second: Void = engine.syncNow()
        _ = await (first, second)

        #expect(remote.commitCount == commitsBefore + 1)
        #expect(remote.filesAtHead(branch: "main")["a.org"] == Data("* TODO edited\n".utf8))
        #expect(engine.status.hasLocalChanges == false)
    }

    @Test func disconnectDoesNotResurrectStateFromInFlightWork() async throws {
        let remote = FakeGitHubRepo()
        remote.seedCommit(branch: "main", changes: ["a.org": Data("v1\n".utf8)])
        let (engine, _, root) = try await connectedEngine(remote: remote)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(engine.isConnected)

        // Start a sync and immediately disconnect; disconnect waits for the
        // in-flight op, so the engine ends disconnected regardless of ordering.
        async let syncing: Void = engine.syncNow()
        await engine.disconnect(deleteLocalFiles: false)
        _ = await syncing

        #expect(engine.isConnected == false)
    }
}
