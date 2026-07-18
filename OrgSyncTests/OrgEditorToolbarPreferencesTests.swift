import Foundation
import Testing
@testable import OrgSync

@Suite struct OrgEditorToolbarPreferencesTests {
    @Test func defaultToolbarOffersCorePlanningAndFormattingCommands() {
        let commands = OrgEditorToolbarPreferences.defaultCommands

        #expect(commands.contains(.headline))
        #expect(commands.contains(.timestamp))
        #expect(commands.contains(.scheduled))
        #expect(commands.contains(.deadline))
        #expect(commands.contains(.bold))
        #expect(commands.contains(.link))
    }

    @Test func customToolbarOrderAndVisibilityPersistWithoutDuplicates() {
        let suiteName = "OrgSyncTests.EditorToolbar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        OrgEditorToolbarPreferences.save([.deadline, .bold, .deadline], defaults: defaults)

        #expect(OrgEditorToolbarPreferences.load(defaults: defaults) == [.deadline, .bold])
    }

    @Test func invalidOrEmptyPersistedCommandsRestoreTheUsefulDefaultSet() {
        let suiteName = "OrgSyncTests.EditorToolbar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(["not-a-command"], forKey: "editorToolbar.commands")

        #expect(OrgEditorToolbarPreferences.load(defaults: defaults) == OrgEditorToolbarPreferences.defaultCommands)
    }

    @Test func untouchedInsertionIsEligibleForReplacementByADifferentCommand() {
        let pending = OrgEditorToolbarInsertionPolicy.pendingInsertion(
            command: .headline,
            before: "Inbox",
            after: "* Inbox"
        )!

        #expect(pending.range == NSRange(location: 0, length: 2))
        #expect(OrgEditorToolbarInsertionPolicy.shouldReplace(pending: pending, with: .checkbox, currentText: "* Inbox"))
        #expect(!OrgEditorToolbarInsertionPolicy.shouldReplace(pending: pending, with: .headline, currentText: "* Inbox"))
        #expect(!OrgEditorToolbarInsertionPolicy.shouldReplace(pending: pending, with: .checkbox, currentText: "* Inbox edited"))
    }
}
