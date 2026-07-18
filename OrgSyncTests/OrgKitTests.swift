//
//  OrgKitTests.swift
//  OrgSyncTests
//
//  Unit tests for OrgKit: parsing each construct, timestamp parse/format,
//  inline emphasis edge cases, TODO keyword configuration, round-trip
//  losslessness, and mutation helpers.
//

import Testing
import Foundation
@testable import OrgSync

// MARK: - Timestamps

@Suite struct OrgTimestampTests {
    @Test func parsesActiveDateOnly() {
        let ts = OrgTimestamp.parse("<2026-07-18 Sat>")
        #expect(ts?.isActive == true)
        #expect(ts?.year == 2026)
        #expect(ts?.month == 7)
        #expect(ts?.day == 18)
        #expect(ts?.dayName == "Sat")
        #expect(ts?.hasTime == false)
    }

    @Test func parsesInactiveWithTime() {
        let ts = OrgTimestamp.parse("[2026-07-18 Sat 10:00]")
        #expect(ts?.isActive == false)
        #expect(ts?.startHour == 10)
        #expect(ts?.startMinute == 0)
    }

    @Test func parsesTimeRange() {
        let ts = OrgTimestamp.parse("<2026-07-18 Sat 10:00-11:30>")
        #expect(ts?.startHour == 10)
        #expect(ts?.endHour == 11)
        #expect(ts?.endMinute == 30)
    }

    @Test func parsesRepeaterAndWarning() {
        let ts = OrgTimestamp.parse("<2026-07-18 Sat 10:00 +1w -2d>")
        #expect(ts?.repeater?.kind == .cumulate)
        #expect(ts?.repeater?.value == 1)
        #expect(ts?.repeater?.unit == .week)
        #expect(ts?.warning?.value == 2)
        #expect(ts?.warning?.unit == .day)
    }

    @Test func parsesCatchUpAndRestartRepeaters() {
        #expect(OrgTimestamp.parse("<2026-07-18 Sat ++1m>")?.repeater?.kind == .catchUp)
        #expect(OrgTimestamp.parse("<2026-07-18 Sat .+1d>")?.repeater?.kind == .restart)
    }

    @Test func parsesRange() {
        let ts = OrgTimestamp.parse("<2026-07-18 Sat>--<2026-07-20 Mon>")
        #expect(ts?.end?.day == 20)
        #expect(ts?.end?.dayName == "Mon")
    }

    @Test func formatsLikeEmacs() {
        let cases = [
            "<2026-07-18 Sat>",
            "<2026-07-18 Sat 10:00>",
            "<2026-07-18 Sat 10:00-11:30>",
            "<2026-07-18 Sat 10:00 +1w>",
            "<2026-07-18 Sat 10:00 +1w -2d>",
            "[2026-07-18 Sat]",
            "<2026-07-18 Sat>--<2026-07-20 Mon>",
        ]
        for text in cases {
            #expect(OrgTimestamp.parse(text)?.serialize() == text, "round-trip \(text)")
        }
    }

    @Test func computesDayNameWhenConstructedFromDate() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 18
        let date = OrgTimestamp.calendar.date(from: comps)!
        let ts = OrgTimestamp(date: date)
        #expect(ts.dayName == "Sat")
        #expect(ts.serialize() == "<2026-07-18 Sat>")
    }

    @Test func advancesCumulateRepeater() {
        let ts = OrgTimestamp.parse("<2026-07-18 Sat +1w>")!
        let next = ts.advancedByRepeater()
        #expect(next.day == 25)
        #expect(next.dayName == "Sat")
        #expect(next.repeater?.text == "+1w")
    }

    @Test func advancesRestartRepeaterFromReference() {
        let ts = OrgTimestamp.parse("<2020-01-01 Wed .+2d>")!
        var refComps = DateComponents()
        refComps.year = 2026; refComps.month = 7; refComps.day = 18
        let ref = OrgTimestamp.calendar.date(from: refComps)!
        let next = ts.advancedByRepeater(reference: ref)
        #expect(next.year == 2026 && next.month == 7 && next.day == 20)
    }

    @Test func advancesCatchUpRepeaterPastReference() {
        let ts = OrgTimestamp.parse("<2026-07-01 Wed ++1w>")!
        var refComps = DateComponents()
        refComps.year = 2026; refComps.month = 7; refComps.day = 18
        let ref = OrgTimestamp.calendar.date(from: refComps)!
        let next = ts.advancedByRepeater(reference: ref)
        // 07-01 -> 07-08 -> 07-15 -> 07-22 (first strictly after 07-18)
        #expect(next.day == 22)
    }
}

// MARK: - Inline markup

@Suite struct OrgInlineTests {
    @Test func parsesBoldItalicUnderline() {
        #expect(OrgInlineParser.parse("*bold*") == [.bold([.text("bold")])])
        #expect(OrgInlineParser.parse("/it/") == [.italic([.text("it")])])
        #expect(OrgInlineParser.parse("_u_") == [.underline([.text("u")])])
        #expect(OrgInlineParser.parse("+s+") == [.strikethrough([.text("s")])])
    }

    @Test func parsesVerbatimAndCodeLiterally() {
        #expect(OrgInlineParser.parse("=verb=") == [.verbatim("verb")])
        #expect(OrgInlineParser.parse("~code~") == [.code("code")])
        // No nested markup inside verbatim.
        #expect(OrgInlineParser.parse("=a*b*c=") == [.verbatim("a*b*c")])
    }

    @Test func respectsWordBoundaries() {
        // Not emphasis: marker touches a letter on the outside.
        let nodes = OrgInlineParser.parse("a*b*c")
        #expect(nodes == [.text("a*b*c")])
    }

    @Test func noEmphasisWithInnerSpaceBoundary() {
        #expect(OrgInlineParser.parse("* not bold*") == [.text("* not bold*")])
        #expect(OrgInlineParser.parse("*not bold *") == [.text("*not bold *")])
    }

    @Test func emphasisAfterAllowedPreChar() {
        let nodes = OrgInlineParser.parse("(*bold*)")
        #expect(nodes == [.text("("), .bold([.text("bold")]), .text(")")])
    }

    @Test func emphasisMidSentence() {
        let nodes = OrgInlineParser.parse("this is *bold* text")
        #expect(nodes == [.text("this is "), .bold([.text("bold")]), .text(" text")])
    }

    @Test func nestedEmphasis() {
        let nodes = OrgInlineParser.parse("*/bi/*")
        #expect(nodes == [.bold([.italic([.text("bi")])])])
    }

    @Test func parsesLinkWithDescription() {
        let nodes = OrgInlineParser.parse("see [[https://x.com][X]] now")
        #expect(nodes == [.text("see "), .link(target: "https://x.com", description: "X"), .text(" now")])
    }

    @Test func parsesBareLink() {
        #expect(OrgInlineParser.parse("[[https://x.com]]") == [.link(target: "https://x.com", description: nil)])
    }

    @Test func parsesPlainURL() {
        let nodes = OrgInlineParser.parse("go to https://x.com.")
        #expect(nodes == [.text("go to "), .plainLink("https://x.com"), .text(".")])
    }

    @Test func inlineRoundTrips() {
        let cases = ["*bold*", "/i/ and =v=", "a [[u][d]] b", "plain text", "~c~ +s+ _u_"]
        for text in cases {
            #expect(OrgInline.serialize(OrgInlineParser.parse(text)) == text, "round-trip \(text)")
        }
    }
}

// MARK: - TODO config

@Suite struct OrgTodoConfigTests {
    @Test func defaultConfig() {
        let c = OrgTodoConfig.default
        #expect(c.allKeywords == ["TODO", "PROGRESS", "WAITING", "DONE"])
        #expect(c.isDone("DONE"))
        #expect(!c.isDone("TODO"))
    }

    @Test func statusPaletteUsesBuiltInsAndTenCustomColors() {
        let builtIn = OrgTodoConfig.default
        #expect(OrgTodoStatusPalette.hex(for: "TODO", configuration: builtIn) == "F59E0B")
        #expect(OrgTodoStatusPalette.hex(for: "PROGRESS", configuration: builtIn) == "3B82F6")
        #expect(OrgTodoStatusPalette.hex(for: "WAITING", configuration: builtIn) == "8B5CF6")
        #expect(OrgTodoStatusPalette.hex(for: "DONE", configuration: builtIn) == "22C55E")

        let custom = OrgTodoConfig(sequences: [OrgTodoConfig.parseSequence(
            "TODO PROGRESS WAITING NEXT BLOCKED REVIEW LATER MAYBE HOLD SOMEDAY PAUSED DELEGATED CANCELLED | DONE"
        )])
        let customKeywords = ["NEXT", "BLOCKED", "REVIEW", "LATER", "MAYBE", "HOLD", "SOMEDAY", "PAUSED", "DELEGATED", "CANCELLED"]
        #expect(customKeywords.map { OrgTodoStatusPalette.hex(for: $0, configuration: custom) }
            == Array(OrgTodoStatusPalette.customHex.prefix(customKeywords.count)))
        #expect(OrgTodoStatusPalette.hex(for: "BLOCKED", configuration: custom,
                                         overrides: ["BLOCKED": "E54666"]) == "E54666")
    }

    @Test func onlyDoneStatusStrikesThroughTitles() {
        #expect(OrgTodoStatusPalette.shouldStrikeThrough("DONE"))
        #expect(OrgTodoStatusPalette.shouldStrikeThrough("done"))
        #expect(!OrgTodoStatusPalette.shouldStrikeThrough("CANCELLED"))
        #expect(!OrgTodoStatusPalette.shouldStrikeThrough("WAITING"))
        #expect(!OrgTodoStatusPalette.shouldStrikeThrough(nil))
    }

    @Test func onlyDoneIsTreatedAsCompletedTask() {
        let document = OrgParser.parse("#+TODO: TODO | DONE CANCELLED\n* CANCELLED Archived\n* DONE Finished\n")
        let items = document.todoItems(filePath: "tasks.org")
        #expect(items.map(\.keyword) == ["CANCELLED", "DONE"])
        #expect(items.map(\.isDone) == [false, true])

        var headline = OrgHeadline(level: 1, todoKeyword: "CANCELLED", title: "Archived")
        headline.setTodoKeyword("CANCELLED", config: document.todoConfig, now: Date(timeIntervalSince1970: 0))
        #expect(headline.planning.closed == nil)
        headline.setTodoKeyword("DONE", config: document.todoConfig, now: Date(timeIntervalSince1970: 0))
        #expect(headline.planning.closed != nil)
    }

    @Test func statusEditorAddsDeletesAndSerializesSafely() {
        var statuses = OrgTodoStatusConfiguration.statuses(from: OrgTodoConfig.defaultPreference)
        statuses = OrgTodoStatusConfiguration.adding("blocked", isDone: false, to: statuses)!
        #expect(statuses.map(\.name) == ["TODO", "PROGRESS", "WAITING", "DONE", "BLOCKED"])
        #expect(OrgTodoStatusConfiguration.preference(from: statuses) == "TODO PROGRESS WAITING BLOCKED | DONE")
        #expect(OrgTodoStatusConfiguration.adding("two words", isDone: false, to: statuses) == nil)
        #expect(OrgTodoStatusConfiguration.adding("todo", isDone: false, to: statuses) == nil)

        let withoutProgress = OrgTodoStatusConfiguration.removing(statuses[1], from: statuses)
        #expect(!withoutProgress.contains { $0.name == "PROGRESS" })
        let onlyOpen = [OrgTodoStatus(name: "TODO", isDone: false), OrgTodoStatus(name: "DONE", isDone: true)]
        #expect(OrgTodoStatusConfiguration.removing(onlyOpen[0], from: onlyOpen) == onlyOpen)
    }

    @Test func parsesCustomSequenceWithSeparator() {
        let seq = OrgTodoConfig.parseSequence("TODO NEXT | DONE CANCELLED")
        #expect(seq.notDone == ["TODO", "NEXT"])
        #expect(seq.done == ["DONE", "CANCELLED"])
    }

    @Test func lastKeywordIsDoneWithoutSeparator() {
        let seq = OrgTodoConfig.parseSequence("TODO DONE")
        #expect(seq.notDone == ["TODO"])
        #expect(seq.done == ["DONE"])
    }

    @Test func stripsFastAccessKeys() {
        let seq = OrgTodoConfig.parseSequence("TODO(t) NEXT(n) | DONE(d)")
        #expect(seq.notDone == ["TODO", "NEXT"])
        #expect(seq.done == ["DONE"])
    }

    @Test func configFromDocumentKeywords() {
        let doc = OrgParser.parse("#+TODO: TODO NEXT | DONE CANCELLED\n")
        #expect(doc.todoConfig.doneKeywords == ["DONE", "CANCELLED"])
        #expect(doc.todoConfig.isKeyword("NEXT"))
    }

    @Test func customKeywordRecognizedInHeadline() {
        let doc = OrgParser.parse("#+TODO: TODO NEXT | DONE\n\n* NEXT Ship it\n")
        #expect(doc.headlines.first?.todoKeyword == "NEXT")
    }
}

// MARK: - Parsing constructs

@Suite struct OrgParseTests {
    @Test func parsesHeadlineComponents() {
        let doc = OrgParser.parse("*** TODO [#A] Buy milk :home:errand:\n")
        let h = doc.headlines.first
        // Nesting: single level-3 headline is a root here.
        #expect(h?.level == 3)
        #expect(h?.todoKeyword == "TODO")
        #expect(h?.priority == "A")
        #expect(h?.title == "Buy milk")
        #expect(h?.tags == ["home", "errand"])
    }

    @Test func buildsHeadlineTree() {
        let doc = OrgParser.parse("* A\n** B\n** C\n*** D\n* E\n")
        #expect(doc.headlines.count == 2)
        #expect(doc.headlines[0].title == "A")
        #expect(doc.headlines[0].children.map(\.title) == ["B", "C"])
        #expect(doc.headlines[0].children[1].children.map(\.title) == ["D"])
        #expect(doc.headlines[1].title == "E")
    }

    @Test func parsesPlanning() {
        let doc = OrgParser.parse("* Task\nSCHEDULED: <2026-07-18 Sat> DEADLINE: <2026-07-20 Mon>\n")
        let p = doc.headlines.first?.planning
        #expect(p?.scheduled?.day == 18)
        #expect(p?.deadline?.day == 20)
    }

    @Test func parsesPropertyDrawer() {
        let text = "* Task\n:PROPERTIES:\n:ID: abc-123\n:Effort: 2:00\n:END:\n"
        let doc = OrgParser.parse(text)
        let props = doc.headlines.first?.propertyDrawer?.properties
        #expect(props?.count == 2)
        #expect(props?.first?.key == "ID")
        #expect(props?.first?.value == "abc-123")
    }

    @Test func parsesParagraph() {
        let doc = OrgParser.parse("Some text here.\nSecond line.\n")
        guard case .paragraph(let p)? = doc.preamble.first else { Issue.record("no paragraph"); return }
        #expect(p.lines == ["Some text here.", "Second line."])
    }

    @Test func parsesPlainList() {
        let doc = OrgParser.parse("- one\n- two\n- three\n")
        guard case .list(let l)? = doc.preamble.first else { Issue.record("no list"); return }
        #expect(l.items.count == 3)
        #expect(l.items.map(\.text) == ["one", "two", "three"])
    }

    @Test func parsesOrderedList() {
        let doc = OrgParser.parse("1. first\n2. second\n")
        guard case .list(let l)? = doc.preamble.first else { Issue.record("no list"); return }
        #expect(l.items[0].isOrdered)
        #expect(l.items[0].bullet == "1.")
    }

    @Test func parsesCheckboxList() {
        let doc = OrgParser.parse("- [ ] todo\n- [X] done\n- [-] partial\n")
        guard case .list(let l)? = doc.preamble.first else { Issue.record("no list"); return }
        #expect(l.items.map(\.checkbox) == [.unchecked, .checked, .partial])
    }

    @Test func parsesNestedList() {
        let doc = OrgParser.parse("- parent\n  - child a\n  - child b\n")
        guard case .list(let l)? = doc.preamble.first else { Issue.record("no list"); return }
        #expect(l.items.count == 1)
        #expect(l.items[0].children.map(\.text) == ["child a", "child b"])
    }

    @Test func parsesTable() {
        let text = "| a | b |\n|---+---|\n| 1 | 2 |\n"
        let doc = OrgParser.parse(text)
        guard case .table(let t)? = doc.preamble.first else { Issue.record("no table"); return }
        #expect(t.rows.count == 3)
        #expect(t.rows[0].cells == ["a", "b"])
        #expect(t.rows[1].isSeparator)
        #expect(t.rows[2].cells == ["1", "2"])
    }

    @Test func parsesSrcBlock() {
        let text = "#+BEGIN_SRC swift\nlet x = 1\n#+END_SRC\n"
        let doc = OrgParser.parse(text)
        guard case .block(let b)? = doc.preamble.first else { Issue.record("no block"); return }
        #expect(b.type == "SRC")
        #expect(b.language == "swift")
        #expect(b.lines == ["let x = 1"])
    }

    @Test func parsesQuoteBlock() {
        let doc = OrgParser.parse("#+BEGIN_QUOTE\nhello\n#+END_QUOTE\n")
        guard case .block(let b)? = doc.preamble.first else { Issue.record("no block"); return }
        #expect(b.type == "QUOTE")
    }

    @Test func parsesKeyword() {
        let doc = OrgParser.parse("#+TITLE: My Notes\n")
        #expect(doc.title == "My Notes")
    }

    @Test func parsesComment() {
        let doc = OrgParser.parse("# a comment\n# another\n")
        guard case .comment(let block)? = doc.preamble.first else { Issue.record("no comment"); return }
        #expect(block == ["# a comment", "# another"])
    }

    @Test func parsesHorizontalRule() {
        let doc = OrgParser.parse("-----\n")
        guard case .horizontalRule? = doc.preamble.first else { Issue.record("no rule"); return }
    }

    @Test func parsesFootnoteDefinition() {
        let doc = OrgParser.parse("[fn:1] The footnote text.\n")
        guard case .footnoteDefinition(let f)? = doc.preamble.first else { Issue.record("no footnote"); return }
        #expect(f.label == "1")
    }

    @Test func parsesGenericDrawer() {
        let doc = OrgParser.parse(":LOGBOOK:\nnote\n:END:\n")
        guard case .drawer(let d)? = doc.preamble.first else { Issue.record("no drawer"); return }
        #expect(d.name == "LOGBOOK")
        #expect(d.lines == ["note"])
    }

    @Test func preservesOddLineAsRaw() {
        let doc = OrgParser.parse(":not-a-drawer no end")
        // An unterminated drawer-looking line stays verbatim.
        #expect(doc.serialize() == ":not-a-drawer no end")
    }
}

// MARK: - Round trip

@Suite struct OrgRoundTripTests {
    static let complexDocument = """
    #+TITLE: Project Notes
    #+TODO: TODO NEXT | DONE CANCELLED

    Intro paragraph with *bold*, /italic/, =verbatim=, and a [[https://x.com][link]].

    * TODO [#A] Ship release :work:urgent:
    SCHEDULED: <2026-07-18 Sat 10:00 +1w> DEADLINE: <2026-07-25 Sat>
    :PROPERTIES:
    :ID: release-1
    :Effort: 4:00
    :END:
    Body text under the headline.

    - [ ] write changelog
    - [X] tag commit
    - [-] update docs
      - [ ] api section
      - [X] readme

    #+BEGIN_SRC swift
    let answer = 42
    #+END_SRC

    ** NEXT Sub task
    Some notes.

    | Name | Score |
    |------+-------|
    | Ann  | 10    |
    | Bob  | 7     |

    * DONE Finished thing
    CLOSED: [2026-07-10 Fri 09:30]

    -----

    # A trailing comment.
    """

    @Test func roundTripsComplexDocument() {
        let doc = OrgParser.parse(Self.complexDocument)
        #expect(doc.serialize() == Self.complexDocument)
    }

    @Test func roundTripsWithTrailingNewline() {
        let text = "* A\nbody\n"
        #expect(OrgParser.parse(text).serialize() == text)
    }

    @Test func roundTripsWithoutTrailingNewline() {
        let text = "* A\nbody"
        #expect(OrgParser.parse(text).serialize() == text)
    }

    @Test func roundTripsEmptyDocument() {
        #expect(OrgParser.parse("").serialize() == "")
    }

    @Test func parsesComplexStructure() {
        let doc = OrgParser.parse(Self.complexDocument)
        #expect(doc.title == "Project Notes")
        #expect(doc.headlines.count == 2)
        #expect(doc.headlines[0].todoKeyword == "TODO")
        #expect(doc.headlines[0].children.first?.todoKeyword == "NEXT")
    }
}

// MARK: - Mutations

@Suite struct OrgMutationTests {
    static func makeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return OrgTimestamp.calendar.date(from: c)!
    }

    @Test func togglesTodoToDoneAddsClosed() {
        var h = OrgHeadline(level: 1, todoKeyword: "TODO", title: "Task")
        h.toggleTodo(config: .default, now: Self.makeDate(2026, 7, 18, 10, 0))
        #expect(h.todoKeyword == "DONE")
        #expect(h.planning.closed != nil)
        #expect(h.planning.closed?.isActive == false)
        #expect(h.planning.closed?.serialize() == "[2026-07-18 Sat 10:00]")
    }

    @Test func reopeningRemovesClosed() {
        var h = OrgHeadline(level: 1, todoKeyword: "TODO", title: "Task")
        h.toggleTodo(config: .default, now: Self.makeDate(2026, 7, 18, 10, 0))
        h.toggleTodo(config: .default)
        #expect(h.todoKeyword == "TODO")
        #expect(h.planning.closed == nil)
    }

    @Test func cyclesThroughCustomSequenceAndWrapsToTodo() {
        let config = OrgTodoConfig(sequences: [OrgTodoConfig.parseSequence("TODO NEXT | DONE")])
        var h = OrgHeadline(level: 1, todoKeyword: nil, title: "Task")
        h.cycleTodo(config: config); #expect(h.todoKeyword == "TODO")
        h.cycleTodo(config: config); #expect(h.todoKeyword == "NEXT")
        h.cycleTodo(config: config); #expect(h.todoKeyword == "DONE")
        h.cycleTodo(config: config); #expect(h.todoKeyword == "TODO")
    }

    @Test func repeaterAdvancesInsteadOfCompleting() {
        var h = OrgHeadline(level: 1, todoKeyword: "TODO", title: "Weekly review")
        h.planning.scheduled = OrgTimestamp.parse("<2026-07-18 Sat +1w>")
        h.toggleTodo(config: .default, now: Self.makeDate(2026, 7, 18))
        // Stays not-done; schedule advanced a week; no CLOSED written.
        #expect(h.todoKeyword == "TODO")
        #expect(h.planning.scheduled?.day == 25)
        #expect(h.planning.closed == nil)
    }

    @Test func setPriorityAndTags() {
        var h = OrgHeadline(level: 1, title: "Task")
        h.setPriority("B")
        h.addTag("work")
        h.addTag("work") // duplicate ignored
        h.addTag("urgent")
        #expect(h.priority == "B")
        #expect(h.tags == ["work", "urgent"])
        h.removeTag("work")
        #expect(h.tags == ["urgent"])
    }

    @Test func setScheduledAndDeadline() {
        var h = OrgHeadline(level: 1, title: "Task")
        h.setScheduled(date: Self.makeDate(2026, 7, 18), includeTime: false)
        h.setDeadline(date: Self.makeDate(2026, 7, 25), includeTime: false)
        #expect(h.planning.scheduled?.serialize() == "<2026-07-18 Sat>")
        #expect(h.planning.deadline?.serialize() == "<2026-07-25 Sat>")
    }

    @Test func mutationRegeneratesHeadingLine() {
        let doc = OrgParser.parse("* TODO Task\n")
        var h = doc.headlines[0]
        h.setPriority("A")
        h.addTag("home")
        #expect(OrgSerializer.regenerateHeading(h) == "* TODO [#A] Task :home:")
    }

    @Test func cyclesCheckboxAndUpdatesParentStatistics() {
        let text = "- [-] parent [1/2]\n  - [ ] a\n  - [X] b\n"
        let doc = OrgParser.parse(text)
        guard case .list(var list) = doc.preamble.first! else { Issue.record("no list"); return }
        // Toggle child "a" (path [0,0]) on.
        list.cycleCheckbox(at: [0, 0])
        #expect(list.items[0].children[0].checkbox == .checked)
        // Parent becomes fully checked; cookie updates to [2/2].
        #expect(list.items[0].checkbox == .checked)
        #expect(list.items[0].text == "parent [2/2]")
    }

    @Test func checkboxPercentCookie() {
        let text = "- [-] parent [0%]\n  - [X] a\n  - [ ] b\n"
        let doc = OrgParser.parse(text)
        guard case .list(var list) = doc.preamble.first! else { Issue.record("no list"); return }
        list.cycleCheckbox(at: [0, 1]) // check b -> 2/2 -> 100%
        #expect(list.items[0].text == "parent [100%]")
        #expect(list.items[0].checkbox == .checked)
    }

    @Test func headlineStatisticsCookie() {
        let text = "* Tasks [0/2]\n- [ ] a\n- [ ] b\n"
        let doc = OrgParser.parse(text)
        var h = doc.headlines[0]
        // Check the first list item, then recompute cookies.
        if case .list(var list) = h.body.first {
            list.cycleCheckbox(at: [0])
            h.body[0] = .list(list)
        }
        h.updateStatisticsCookies()
        #expect(h.title == "Tasks [1/2]")
    }
}

// MARK: - Queries

@Suite struct OrgQueryTests {
    @Test func listsTodoHeadlinesWithOutline() {
        let text = "* Project\n** TODO Alpha\n** DONE Beta\n"
        let doc = OrgParser.parse(text)
        let items = doc.todoItems(filePath: "notes/p.org")
        #expect(items.count == 2)
        #expect(items[0].keyword == "TODO")
        #expect(items[0].isDone == false)
        #expect(items[0].outline.headingPath == ["Project", "Alpha"])
        #expect(items[0].outline.filePath == "notes/p.org")
        #expect(items[1].isDone)
    }

    @Test func findsHeadlineByOutline() {
        let text = "* A\n** TODO Deep\n"
        let doc = OrgParser.parse(text)
        let outline = OrgOutline(filePath: "x.org", headingPath: ["A", "Deep"])
        #expect(doc.headline(at: outline)?.title == "Deep")
    }

    @Test func disambiguatesDuplicateHeadingPaths() {
        let text = "* Dup\n* Dup\n"
        let doc = OrgParser.parse(text)
        let outlines = doc.allOutlines(filePath: "x.org")
        #expect(outlines[0].index == 0)
        #expect(outlines[1].index == 1)
    }

    @Test func mutatesHeadlineByOutline() {
        var doc = OrgParser.parse("* TODO First\n* TODO Second\n")
        let outline = OrgOutline(filePath: "x.org", headingPath: ["Second"], index: 0)
        let didMutate = doc.mutateHeadline(at: outline) { headline in
            headline.setPriority("A")
        }
        #expect(didMutate)
        #expect(doc.headlines[0].priority == nil)
        #expect(doc.headlines[1].priority == "A")
    }

    @Test func todoOutlineCountsNonTodoDuplicateHeadings() {
        let doc = OrgParser.parse("* Task\n* TODO Task\n")
        let items = doc.todoItems(filePath: "x.org")
        #expect(items.count == 1)
        #expect(items[0].outline.index == 1)
    }

    @Test func ensuresPersistentIDsForTodoHeadlines() {
        var doc = OrgParser.parse("* TODO Durable task\n")
        let firstChange = doc.ensurePersistentIDsForTodoHeadlines()
        #expect(firstChange)
        #expect(doc.headlines[0].persistentID != nil)
        let secondChange = doc.ensurePersistentIDsForTodoHeadlines()
        #expect(!secondChange)
    }

    @Test func collectsAllTimestamps() {
        let text = """
        * TODO Task
        SCHEDULED: <2026-07-18 Sat> DEADLINE: <2026-07-25 Sat>
        Meeting <2026-07-19 Sun 09:00> in the body.
        """
        let doc = OrgParser.parse(text)
        let stamps = doc.allTimestamps()
        #expect(stamps.count == 3)
    }

    @Test func documentTitle() {
        #expect(OrgParser.parse("#+TITLE: Hello\n").title == "Hello")
        #expect(OrgParser.parse("* No title\n").title == nil)
    }
}
