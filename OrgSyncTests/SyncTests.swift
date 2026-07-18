//
//  SyncTests.swift
//  OrgSyncTests
//
//  Unit tests for the Phase 4 sync building blocks: GitHub URL parsing, local
//  git blob SHA computation, the three-way line merge (clean + conflict), and
//  the persisted sync-state Codable round-trip.
//

import Testing
import Foundation
@testable import OrgSync

// MARK: - Repository URL parsing

@Suite struct RepositoryURLParsingTests {
    @Test func parsesHTTPSURL() throws {
        let (owner, repo) = try GitHubClient.parseRepository("https://github.com/memohnsen/org")
        #expect(owner == "memohnsen")
        #expect(repo == "org")
    }

    @Test func parsesHTTPSURLWithGitSuffix() throws {
        let (owner, repo) = try GitHubClient.parseRepository("https://github.com/memohnsen/org.git")
        #expect(owner == "memohnsen")
        #expect(repo == "org")
    }

    @Test func parsesShorthand() throws {
        let (owner, repo) = try GitHubClient.parseRepository("memohnsen/org")
        #expect(owner == "memohnsen")
        #expect(repo == "org")
    }

    @Test func parsesSSHForm() throws {
        let (owner, repo) = try GitHubClient.parseRepository("git@github.com:memohnsen/org.git")
        #expect(owner == "memohnsen")
        #expect(repo == "org")
    }

    @Test func parsesWithTrailingSlashAndPath() throws {
        let (owner, repo) = try GitHubClient.parseRepository("https://github.com/memohnsen/org/")
        #expect(owner == "memohnsen")
        #expect(repo == "org")
    }

    @Test func rejectsEmpty() {
        #expect(throws: GitHubError.self) {
            _ = try GitHubClient.parseRepository("")
        }
    }

    @Test func rejectsOwnerOnly() {
        #expect(throws: GitHubError.self) {
            _ = try GitHubClient.parseRepository("justowner")
        }
    }
}

// MARK: - Git blob SHA-1

@Suite struct GitBlobHashTests {
    @Test func emptyBlobMatchesGit() {
        // `git hash-object` of an empty file.
        #expect(GitBlob.sha1(for: "") == "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
    }

    @Test func helloBlobMatchesGit() {
        // `printf 'hello\n' | git hash-object --stdin`
        #expect(GitBlob.sha1(for: "hello\n") == "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    @Test func dataAndTextAgree() {
        let text = "* TODO write tests\n"
        #expect(GitBlob.sha1(for: text) == GitBlob.sha1(for: Data(text.utf8)))
    }
}

// MARK: - Three-way merge

@Suite struct ThreeWayMergeTests {
    @Test func cleanMergeOfDisjointEdits() {
        let base = ["line1", "line2", "line3"]
        let local = ["line1-mod", "line2", "line3"]
        let remote = ["line1", "line2", "line3-mod"]
        let result = ThreeWayMerge.merge(base: base, local: local, remote: remote)
        #expect(result.hasConflict == false)
        #expect(result.lines == ["line1-mod", "line2", "line3-mod"])
    }

    @Test func identicalEditsDoNotConflict() {
        let base = ["a", "b", "c"]
        let both = ["a", "B", "c"]
        let result = ThreeWayMerge.merge(base: base, local: both, remote: both)
        #expect(result.hasConflict == false)
        #expect(result.lines == ["a", "B", "c"])
    }

    @Test func overlappingEditsConflict() {
        let base = ["a", "b", "c"]
        let local = ["a", "B-local", "c"]
        let remote = ["a", "B-remote", "c"]
        let result = ThreeWayMerge.merge(base: base, local: local, remote: remote)
        #expect(result.hasConflict == true)
    }

    @Test func onlyLocalChangedKeepsLocal() {
        let base = ["a", "b", "c"]
        let local = ["a", "b", "c", "d"]
        let remote = ["a", "b", "c"]
        let result = ThreeWayMerge.merge(base: base, local: local, remote: remote)
        #expect(result.hasConflict == false)
        #expect(result.lines == ["a", "b", "c", "d"])
    }

    @Test func textConvenienceRoundTrips() {
        let base = "one\ntwo\nthree"
        let local = "one\ntwo!\nthree"
        let remote = "one\ntwo\nthree!"
        let merged = ThreeWayMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.hasConflict == false)
        #expect(merged.text == "one\ntwo!\nthree!")
    }
}

// MARK: - Sync state Codable

@Suite struct SyncStateCodableTests {
    @Test func roundTripsThroughJSON() throws {
        let original = SyncRepoState(
            owner: "memohnsen",
            repo: "org",
            branch: "main",
            baseCommitSHA: "abc123",
            files: ["inbox.org": "sha1", "notes/reading.org": "sha2"],
            skippedPaths: ["big.pdf"],
            lastSyncDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(SyncRepoState.self, from: data)

        #expect(restored == original)
    }
}
