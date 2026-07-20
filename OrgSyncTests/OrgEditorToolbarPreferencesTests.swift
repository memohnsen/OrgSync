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
        #expect(commands.contains(.recurrence))
        #expect(commands.contains(.bold))
        #expect(commands.contains(.link))
        #expect(commands.contains(.table))
    }

    @Test func tableCommandInsertsAnOrgTableSkeletonOnItsOwnLines() {
        let skeleton = "| Header | Header |\n|--------+--------|\n|        |        |"

        // Caret at the end of an existing populated line: the block is pushed
        // onto a fresh line and the caret lands inside the first header cell.
        let onPopulatedLine = OrgEditorTextInsertion.applying(
            .table,
            to: "Notes",
            selection: NSRange(location: 5, length: 0),
            timestamp: "<2026-07-18 Sat>"
        )
        #expect(onPopulatedLine.text == "Notes\n\(skeleton)")
        #expect(onPopulatedLine.selection == NSRange(location: ("Notes\n" as NSString).length + 2, length: 0))

        // On an already-empty line no extra leading newline is added.
        let onEmptyLine = OrgEditorTextInsertion.applying(
            .table,
            to: "",
            selection: NSRange(location: 0, length: 0),
            timestamp: "<2026-07-18 Sat>"
        )
        #expect(onEmptyLine.text == skeleton)
        #expect(onEmptyLine.selection == NSRange(location: 2, length: 0))
    }

    @Test func tableCommandSeparatesFromSurroundingContentOnBothSides() {
        let skeleton = "| Header | Header |\n|--------+--------|\n|        |        |"
        let result = OrgEditorTextInsertion.applying(
            .table,
            to: "Before\nAfter",
            selection: NSRange(location: 6, length: 0),
            timestamp: "<2026-07-18 Sat>"
        )

        #expect(result.text == "Before\n\(skeleton)\nAfter")
    }

    @Test func customToolbarOrderAndVisibilityPersistWithoutDuplicates() {
        let suiteName = "OrgSyncTests.EditorToolbar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        OrgEditorToolbarPreferences.save([.deadline, .bold, .deadline], defaults: defaults)

        #expect(OrgEditorToolbarPreferences.load(defaults: defaults) == [.deadline, .recurrence, .bold])
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
            before: "",
            after: "* "
        )!

        #expect(pending.range == NSRange(location: 0, length: 2))
        #expect(OrgEditorToolbarInsertionPolicy.action(pending: pending, with: .checkbox, currentText: "* ") == .replace)
        #expect(OrgEditorToolbarInsertionPolicy.action(pending: pending, with: .headline, currentText: "* ") == .remove)
        #expect(OrgEditorToolbarInsertionPolicy.action(pending: pending, with: .checkbox, currentText: "* edited") == .none)
    }

    @Test func populatedLinesNeverMarkToolbarInsertionsAsReplaceable() {
        #expect(OrgEditorToolbarInsertionPolicy.pendingInsertion(
            command: .scheduled,
            before: "* TODO Write report",
            after: "* TODO Write report SCHEDULED: <2026-07-18 Sat>"
        ) == nil)
    }

    @Test func everyInlineInsertionCommandReplacesTheSelectionAndPlacesTheCaretIntentionally() {
        let timestamp = "<2026-07-18 Sat>"
        let cases: [(OrgEditorCommand, String, Int)] = [
            (.timestamp, timestamp, 0),
            (.scheduled, "SCHEDULED: \(timestamp)", 0),
            (.deadline, "DEADLINE: \(timestamp)", 0),
            (.recurrence, "+1w", 0),
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
        #expect(scheduled.text == "* TODO Write SCHEDULED: \(timestamp) report")
        #expect(scheduled.selection.location == caret + 1 + ("SCHEDULED: \(timestamp)" as NSString).length)

        let deadline = OrgEditorTextInsertion.applying(
            .deadline,
            to: original,
            selection: NSRange(location: caret, length: 0),
            timestamp: timestamp
        )
        #expect(deadline.text == "* TODO Write DEADLINE: \(timestamp) report")
        #expect(deadline.selection.location == caret + 1 + ("DEADLINE: \(timestamp)" as NSString).length)
    }

    @Test func consecutivePlanningInsertionsOnAPopulatedLineAreAdditiveAndSeparated() {
        let timestamp = "<2026-07-18 Sat>"
        let original = "* TODO Write report"
        let first = OrgEditorTextInsertion.applying(
            .scheduled,
            to: original,
            selection: NSRange(location: (original as NSString).length, length: 0),
            timestamp: timestamp
        )
        let second = OrgEditorTextInsertion.applying(
            .deadline,
            to: first.text,
            selection: first.selection,
            timestamp: timestamp
        )

        #expect(second.text == "* TODO Write report SCHEDULED: \(timestamp) DEADLINE: \(timestamp)")
    }

    @Test func priorityInsertsImmediatelyAfterAHeadlineStatus() {
        let result = OrgEditorTextInsertion.applying(
            .priority,
            to: "* TODO Write the release notes",
            selection: NSRange(location: 28, length: 0),
            timestamp: "<2026-07-18 Sat>",
            todoKeywords: ["TODO", "PROGRESS", "WAITING", "DONE"]
        )

        #expect(result.text == "* TODO [#A] Write the release notes")
        #expect(result.selection == NSRange(location: 11, length: 0))
    }

    @Test func priorityKeepsCaretBasedInsertionWhenTheLineHasNoRecognizedStatus() {
        let result = OrgEditorTextInsertion.applying(
            .priority,
            to: "Meeting notes",
            selection: NSRange(location: 7, length: 0),
            timestamp: "<2026-07-18 Sat>",
            todoKeywords: ["TODO"]
        )

        #expect(result.text == "Meeting [#A] notes")
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

        #expect(result.text == "🦄 :tag: café")
        #expect(result.selection == NSRange(location: selection.location + 4, length: 0))
    }

    @Test func invalidSelectionsAreClampedRatherThanCrashingTextEntry() {
        let result = OrgEditorTextInsertion.applying(
            .timestamp,
            to: "Inbox",
            selection: NSRange(location: 99, length: 3),
            timestamp: "<2026-07-18 Sat>"
        )

        #expect(result.text == "Inbox <2026-07-18 Sat>")
        #expect(result.selection == NSRange(location: (result.text as NSString).length, length: 0))
    }
}
