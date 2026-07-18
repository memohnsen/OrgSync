import Foundation
import Testing
@testable import OrgSync

@Suite struct ReviewRequestPolicyTests {
    @Test func connectionPromptIsEligibleOnlyOnce() {
        let suiteName = "OrgSyncTests.ReviewPrompt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ReviewRequestPolicy.shouldRequestAfterRepositoryConnection(defaults: defaults))
        #expect(!ReviewRequestPolicy.shouldRequestAfterRepositoryConnection(defaults: defaults))
    }

    @Test func tenthDistinctEditedNoteRequestsReviewOnlyOnce() {
        let suiteName = "OrgSyncTests.ReviewPrompt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for index in 1...9 {
            #expect(!ReviewRequestPolicy.shouldRequestAfterEditingNote(path: "note-\(index).org", defaults: defaults))
        }
        #expect(ReviewRequestPolicy.shouldRequestAfterEditingNote(path: "note-10.org", defaults: defaults))
        #expect(!ReviewRequestPolicy.shouldRequestAfterEditingNote(path: "note-10.org", defaults: defaults))
        #expect(!ReviewRequestPolicy.shouldRequestAfterEditingNote(path: "note-11.org", defaults: defaults))
    }
}
