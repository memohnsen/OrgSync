//
//  WikiLinkTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct WikiLinkTests {
    @Test func extractsTargetsWithAndWithoutDescriptions() {
        let text = "See [[reading]] and [[notes/ideas][my ideas]] plus [[https://x.com][site]]."
        #expect(WikiLink.targets(in: text) == ["reading", "notes/ideas", "https://x.com"])
    }

    @Test func resolvesByNameAndPathIgnoringExtensionAndFilePrefix() {
        #expect(WikiLink.resolves("reading", toNoteNamed: "reading", relativePath: "notes/reading.org"))
        #expect(WikiLink.resolves("reading.org", toNoteNamed: "reading", relativePath: "notes/reading.org"))
        #expect(WikiLink.resolves("file:notes/reading.org", toNoteNamed: "reading", relativePath: "notes/reading.org"))
        #expect(WikiLink.resolves("Reading", toNoteNamed: "reading", relativePath: "notes/reading.org"))
        #expect(!WikiLink.resolves("other", toNoteNamed: "reading", relativePath: "notes/reading.org"))
    }

    @Test func nonNoteTargetsDoNotResolve() {
        #expect(!WikiLink.resolves("*Some Heading", toNoteNamed: "reading", relativePath: "reading.org"))
        #expect(!WikiLink.resolves("id:1234", toNoteNamed: "reading", relativePath: "reading.org"))
        #expect(!WikiLink.resolves("https://reading.org", toNoteNamed: "reading", relativePath: "reading.org"))
    }
}

@MainActor
@Suite(.serialized) struct RepoStoreBacklinkTests {
    @Test func backlinksFindReferencingNotesAndExcludeSelf() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = RepoStore(repoURL: root, seedsSampleContent: false)
        try "#+TITLE: Reading\n* A book\n".write(to: root.appendingPathComponent("reading.org"), atomically: true, encoding: .utf8)
        try "* Note\nSee [[reading]] for more.\n".write(to: root.appendingPathComponent("projects.org"), atomically: true, encoding: .utf8)
        try "* Also here\n[[reading][the reading list]]\n".write(to: root.appendingPathComponent("journal.org"), atomically: true, encoding: .utf8)
        try "* Unrelated\nno links here\n".write(to: root.appendingPathComponent("misc.org"), atomically: true, encoding: .utf8)
        repo.refresh()

        let reading = try #require(repo.item(forRelativePath: "reading.org"))
        let names = repo.backlinks(to: reading).map(\.displayName)
        #expect(names == ["journal", "projects"])
    }
}
