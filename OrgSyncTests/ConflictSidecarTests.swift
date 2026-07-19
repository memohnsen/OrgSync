//
//  ConflictSidecarTests.swift
//  OrgSyncTests
//

import Testing
@testable import OrgSync

@Suite struct ConflictSidecarTests {
    @Test func nameTagsWithShortSHAAndPreservesExtension() {
        #expect(ConflictSidecar.name(for: "notes.org", remoteSHA: "abcdef1234567") == "notes (conflict abcdef1).org")
        #expect(ConflictSidecar.name(for: "README", remoteSHA: "abcdef1234567") == "README (conflict abcdef1)")
    }

    @Test func isSidecarDetectsNamesAndPaths() {
        #expect(ConflictSidecar.isSidecar("notes (conflict abcdef1).org"))
        #expect(ConflictSidecar.isSidecar("folder/notes (conflict abcdef1).org"))
        #expect(!ConflictSidecar.isSidecar("notes.org"))
    }

    @Test func nameAndOriginalNameRoundTrip() {
        for fileName in ["notes.org", "README", "a.b.org", "with space.md"] {
            let sidecar = ConflictSidecar.name(for: fileName, remoteSHA: "0123456789")
            #expect(ConflictSidecar.originalName(ofSidecar: sidecar) == fileName)
        }
    }

    @Test func originalNameIsNilForNonSidecar() {
        #expect(ConflictSidecar.originalName(ofSidecar: "notes.org") == nil)
    }
}
