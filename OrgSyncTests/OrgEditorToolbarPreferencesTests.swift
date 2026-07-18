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
        #expect(OrgEditorToolbarInsertionPolicy.action(pending: pending, with: .checkbox, currentText: "* Inbox") == .replace)
        #expect(OrgEditorToolbarInsertionPolicy.action(pending: pending, with: .headline, currentText: "* Inbox") == .remove)
        #expect(OrgEditorToolbarInsertionPolicy.action(pending: pending, with: .checkbox, currentText: "* Inbox edited") == .none)
    }

    @Test func everyInlineInsertionCommandReplacesTheSelectionAndPlacesTheCaretIntentionally() {
        let timestamp = "<2026-07-18 Sat>"
        let cases: [(OrgEditorCommand, String, Int)] = [
            (.timestamp, timestamp, 0),
            (.scheduled, "SCHEDULED: \(timestamp)", 0),
            (.deadline, "DEADLINE: \(timestamp)", 0),
            (.priority, "[#A] ", 0),
            (.tag, ":tag:", 1),
            (.link, "[[][]]", 4),
            (.sourceBlock, "#+begin_src\n\n#+end_src", 10),
        ]

        for (command, snippet, caretOffset) in cases {
            let result = OrgEditorTextInsertion.applying(
                command,
                to: "abCD",
                selection: NSRange(location: 2, length: 1),
                timestamp: timestamp
            )

            #expect(result.text == "ab\(snippet)D", "\(command.title) should replace the selected text")
            #expect(result.selection == NSRange(location: 2 + (snippet as NSString).length - caretOffset, length: 0),
                    "\(command.title) should leave the caret in its editable position")
        }
    }

    @Test func allLinePrefixCommandsInsertAtTheActiveLineWithoutMovingTextFromOtherLines() {
        let cases: [(OrgEditorCommand, String)] = [
            (.headline, "* "),
            (.todo, "* TODO "),
            (.checkbox, "- [ ] "),
            (.comment, "# "),
        ]

        for (command, prefix) in cases {
            let result = OrgEditorTextInsertion.applying(
                command,
                to: "Inbox\nWrite report\nArchive",
                selection: NSRange(location: 10, length: 4),
                timestamp: "<2026-07-18 Sat>"
            )

            #expect(result.text == "Inbox\n\(prefix)Write report\nArchive")
            #expect(result.selection == NSRange(location: 10 + (prefix as NSString).length, length: 0))
        }
    }

    @Test func scheduledAndDeadlineInsertAtTheCaretInsideAnExistingTodoHeadline() {
        let timestamp = "<2026-07-18 Sat>"
        let original = "* TODO Write report"
        let caret = ("* TODO Write" as NSString).length

        let scheduled = OrgEditorTextInsertion.applying(
            .scheduled,
            to: original,
            selection: NSRange(location: caret, length: 0),
            timestamp: timestamp
        )
        #expect(scheduled.text == "* TODO WriteSCHEDULED: \(timestamp) report")
        #expect(scheduled.selection.location == caret + ("SCHEDULED: \(timestamp)" as NSString).length)

        let deadline = OrgEditorTextInsertion.applying(
            .deadline,
            to: original,
            selection: NSRange(location: caret, length: 0),
            timestamp: timestamp
        )
        #expect(deadline.text == "* TODO WriteDEADLINE: \(timestamp) report")
        #expect(deadline.selection.location == caret + ("DEADLINE: \(timestamp)" as NSString).length)
    }

    @Test func allFormattingCommandsWrapAnExistingSelectionAndPlaceTheCaretAfterIt() {
        let cases: [(OrgEditorCommand, String)] = [
            (.bold, "*"), (.italic, "/"), (.underline, "_"), (.strike, "+"), (.code, "~"),
        ]

        for (command, marker) in cases {
            let result = OrgEditorTextInsertion.applying(
                command,
                to: "Plan today",
                selection: NSRange(location: 5, length: 5),
                timestamp: "<2026-07-18 Sat>"
            )
            #expect(result.text == "Plan \(marker)today\(marker)")
            #expect(result.selection == NSRange(location: 12, length: 0))
        }
    }

    @Test func allFormattingCommandsLeaveTheCaretInsideEmptyMarkers() {
        let cases: [(OrgEditorCommand, String)] = [
            (.bold, "*"), (.italic, "/"), (.underline, "_"), (.strike, "+"), (.code, "~"),
        ]

        for (command, marker) in cases {
            let result = OrgEditorTextInsertion.applying(
                command,
                to: "Plan",
                selection: NSRange(location: 2, length: 0),
                timestamp: "<2026-07-18 Sat>"
            )
            #expect(result.text == "Pl\(marker)\(marker)an")
            #expect(result.selection == NSRange(location: 3, length: 0))
        }
    }

    @Test func insertionUsesUTF16RangesSoEmojiAndAccentedTextDoNotMisplaceTheCaret() {
        let original = "🦄 café"
        let selection = NSRange(location: ("🦄 " as NSString).length, length: 0)
        let result = OrgEditorTextInsertion.applying(
            .tag,
            to: original,
            selection: selection,
            timestamp: "<2026-07-18 Sat>"
        )

        #expect(result.text == "🦄 :tag:café")
        #expect(result.selection == NSRange(location: selection.location + 4, length: 0))
    }

    @Test func invalidSelectionsAreClampedRatherThanCrashingTextEntry() {
        let result = OrgEditorTextInsertion.applying(
            .timestamp,
            to: "Inbox",
            selection: NSRange(location: 99, length: 3),
            timestamp: "<2026-07-18 Sat>"
        )

        #expect(result.text == "Inbox<2026-07-18 Sat>")
        #expect(result.selection == NSRange(location: (result.text as NSString).length, length: 0))
    }
}
