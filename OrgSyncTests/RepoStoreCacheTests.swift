//
//  RepoStoreCacheTests.swift
//  OrgSyncTests
//
//  Verifies the RepoStore document parse cache: reuse on repeated reads,
//  invalidation on write, and full invalidation on external refresh.
//

import Foundation
import Testing
@testable import OrgSync

@MainActor
@Suite(.serialized) struct RepoStoreCacheTests {
    private func makeRepo() -> (RepoStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = RepoStore(repoURL: root, seedsSampleContent: false)
        return (repo, root)
    }

    @Test func repeatedReadsParseOnce() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "* TODO Alpha\n".write(to: root.appendingPathComponent("a.org"), atomically: true, encoding: .utf8)
        let item = try #require(repo.item(forRelativePath: "a.org"))

        _ = repo.document(of: item)
        _ = repo.document(of: item)
        _ = repo.document(of: item)
        #expect(repo.parseCount == 1)
    }

    @Test func allTodoItemsParsesEachFileOncePerCall() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "* TODO One\n".write(to: root.appendingPathComponent("a.org"), atomically: true, encoding: .utf8)
        try "* TODO Two\n".write(to: root.appendingPathComponent("b.org"), atomically: true, encoding: .utf8)

        _ = repo.allTodoItems()
        #expect(repo.parseCount == 2)
        // Second pass is fully served from cache.
        _ = repo.allTodoItems()
        #expect(repo.parseCount == 2)
    }

    @Test func writeReparsesOnlyTheChangedFile() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "* TODO Before\n".write(to: root.appendingPathComponent("a.org"), atomically: true, encoding: .utf8)
        try "* TODO Untouched\n".write(to: root.appendingPathComponent("b.org"), atomically: true, encoding: .utf8)

        _ = repo.allTodoItems()
        #expect(repo.parseCount == 2)

        let item = try #require(repo.item(forRelativePath: "a.org"))
        // The write triggers a snapshot rebuild, which re-parses the changed
        // file (a.org) but reuses the cached b.org — one additional parse.
        #expect(repo.write("* TODO After\n", to: item))
        #expect(repo.parseCount == 3)

        // Reading the changed file afterwards is a cache hit with fresh content.
        let updated = repo.document(of: try #require(repo.item(forRelativePath: "a.org")))
        #expect(repo.parseCount == 3)
        #expect(updated.todoItems(filePath: "a.org").first?.title == "After")
    }

    @Test func refreshClearsTheWholeCache() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "* TODO One\n".write(to: root.appendingPathComponent("a.org"), atomically: true, encoding: .utf8)
        try "* TODO Two\n".write(to: root.appendingPathComponent("b.org"), atomically: true, encoding: .utf8)
        _ = repo.allTodoItems()
        #expect(repo.parseCount == 2)

        // An external writer (e.g. sync) changes files on disk, then refresh().
        try "* TODO One edited\n".write(to: root.appendingPathComponent("a.org"), atomically: true, encoding: .utf8)
        repo.refresh()
        _ = repo.allTodoItems()
        #expect(repo.parseCount == 4)
    }

    @Test func modificationDateChangeReparsesWithoutExplicitInvalidation() throws {
        let (repo, root) = makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.org")
        try "* TODO One\n".write(to: url, atomically: true, encoding: .utf8)
        _ = repo.document(of: try #require(repo.item(forRelativePath: "a.org")))
        #expect(repo.parseCount == 1)

        // Simulate an out-of-band change with a distinctly newer modification date.
        try "* TODO Two\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        let refreshed = try #require(repo.item(forRelativePath: "a.org"))
        _ = repo.document(of: refreshed)
        #expect(repo.parseCount == 2)
    }
}
