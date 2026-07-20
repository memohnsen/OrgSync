//
//  RepoStoreSearchTests.swift
//  OrgSyncTests
//
//  Verifies full-text note search: filename vs. content matches, and the
//  snippet extraction shown under each search result.
//

import Foundation
import Testing
@testable import OrgSync

@MainActor
@Suite(.serialized) struct RepoStoreSearchTests {
    private func makeRepo() -> (RepoStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = RepoStore(repoURL: root, seedsSampleContent: false)
        return (repo, root)
    }

    // MARK: - Search results

    @Test func contentMatchCarriesTheMatchingLineAsSnippet() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "* Groceries\n- buy oat milk\n- eggs\n".write(to: root.appendingPathComponent("shopping.org"), atomically: true, encoding: .utf8)

        let results = repo.search("oat milk", under: root)
        #expect(results.count == 1)
        #expect(results.first?.item.relativePath == "shopping.org")
        #expect(results.first?.snippet == "- buy oat milk")
    }

    @Test func filenameOnlyMatchHasNoSnippet() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "* Nothing relevant here\n".write(to: root.appendingPathComponent("recipes.org"), atomically: true, encoding: .utf8)

        let results = repo.search("recipes", under: root)
        #expect(results.count == 1)
        #expect(results.first?.snippet == nil)
    }

    @Test func searchIsCaseInsensitiveAndRecursesIntoSubfolders() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "* Standup Notes\nDiscussed ROADMAP today\n".write(to: sub.appendingPathComponent("standup.org"), atomically: true, encoding: .utf8)

        let results = repo.search("roadmap", under: root)
        #expect(results.count == 1)
        #expect(results.first?.item.relativePath == "work/standup.org")
        #expect(results.first?.snippet == "Discussed ROADMAP today")
    }

    @Test func nonMatchingAndNonOrgFilesAreExcluded() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "no hits here\n".write(to: root.appendingPathComponent("a.org"), atomically: true, encoding: .utf8)
        try "zebra\n".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        #expect(repo.search("zebra", under: root).isEmpty)
        #expect(repo.search("   ", under: root).isEmpty)
    }

    // MARK: - Snippet extraction

    @Test func snippetPicksFirstMatchingLineTrimmed() {
        let text = "* Heading\n   indented match here   \nmatch again later\n"
        #expect(RepoStore.snippet(for: "match", in: text) == "indented match here")
    }

    @Test func snippetIsNilWhenTextDoesNotContainQuery() {
        #expect(RepoStore.snippet(for: "absent", in: "some other text\n") == nil)
    }

    @Test func snippetElidesLongLeadingTextSoMatchStaysVisible() throws {
        let line = String(repeating: "x", count: 60) + " needle in the haystack"
        let unwrapped = try #require(RepoStore.snippet(for: "needle", in: line))
        #expect(unwrapped.hasPrefix("…"))
        #expect(unwrapped.contains("needle in the haystack"))
        // The elision keeps only a short context window before the match.
        let lead = unwrapped.distance(from: unwrapped.startIndex,
                                      to: unwrapped.range(of: "needle")!.lowerBound)
        #expect(lead <= 30)
    }

    @Test func snippetMatchNearLineStartKeepsWholeLine() {
        let line = "short needle line"
        #expect(RepoStore.snippet(for: "needle", in: line) == line)
    }
}
