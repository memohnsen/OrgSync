//
//  SyncWorkerFlowTests.swift
//  OrgSyncTests
//
//  End-to-end SyncWorker flows (connect/pull/commit/push) against the in-memory
//  FakeGitHub remote. These cover the sync invariants the app depends on:
//  deletions survive pulls, skipped paths persist, and the post-push baseline
//  matches what was actually uploaded.
//

import Foundation
import Testing
@testable import OrgSync

private func makeWorkingCopy() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Suite struct SyncWorkerPullTests {
    @Test func localDeletionSurvivesUnrelatedRemoteCommitAndIsPushed() async throws {
        let remote = FakeGitHubRepo()
        remote.seedCommit(branch: "main", changes: [
            "a.org": Data("alpha\n".utf8),
            "b.org": Data("beta\n".utf8),
        ])
        let root = try makeWorkingCopy()
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = SyncWorker(repoURL: root)
        let client = remote.makeClient()
        var result = try await worker.connect(branch: "main", owner: remote.owner, repo: remote.repo, client: client)

        // Delete a note locally, then land an unrelated remote commit.
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.org"))
        remote.seedCommit(branch: "main", changes: ["b.org": Data("beta v2\n".utf8)])

        result = try await worker.pull(state: result.state, client: client)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("a.org").path),
                "pull must not resurrect a locally deleted file")
        #expect(result.status.deleted == ["a.org"],
                "the local deletion must remain a visible local change after pull")

        // Sync should now push the deletion to the remote.
        result = try await worker.sync(state: result.state, client: client)
        #expect(remote.filesAtHead(branch: "main").keys.sorted() == ["b.org"])
        #expect(result.status.hasLocalChanges == false)

        // And a further pull must not bring the file back.
        result = try await worker.pull(state: result.state, client: client)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("a.org").path))
        #expect(result.status.hasLocalChanges == false)
    }

    @Test func skippedLargeFileSurvivesUnrelatedPull() async throws {
        let remote = FakeGitHubRepo()
        let bigData = Data(repeating: 0x42, count: 64)
        remote.seedCommit(branch: "main", changes: [
            "big.bin": bigData,
            "note.org": Data("hi\n".utf8),
        ])
        let root = try makeWorkingCopy()
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = SyncWorker(repoURL: root, maxBlobDownloadBytes: 16)
        let client = remote.makeClient()
        var result = try await worker.connect(branch: "main", owner: remote.owner, repo: remote.repo, client: client)
        #expect(result.state.skippedPaths == ["big.bin"])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("big.bin").path))

        remote.seedCommit(branch: "main", changes: ["note.org": Data("hi v2\n".utf8)])
        result = try await worker.pull(state: result.state, client: client)
        #expect(result.state.skippedPaths == ["big.bin"],
                "an undownloaded large file must stay tracked as skipped across pulls")
        #expect(result.state.files["big.bin"] == GitBlob.sha1(for: bigData))
        #expect(result.status.hasLocalChanges == false,
                "a skipped path must not be misreported as a local deletion")
    }
}
