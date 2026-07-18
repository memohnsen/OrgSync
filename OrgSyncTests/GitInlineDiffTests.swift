import Testing
@testable import OrgSync

@Suite struct GitInlineDiffTests {
    @Test func keepsContextOnceAndMarksOnlyChangedLines() {
        let lines = GitInlineDiff.lines(original: "one\ntwo\nthree\n", current: "one\nupdated\nthree\n")
        #expect(lines.map(\.text) == ["one", "two", "updated", "three", ""])
        #expect(lines.map(\.kind) == [.unchanged, .removed, .added, .unchanged, .unchanged])
    }

    @Test func representsAddedAndDeletedFiles() {
        #expect(GitInlineDiff.lines(original: nil, current: "new\n").map(\.kind) == [.added, .added])
        #expect(GitInlineDiff.lines(original: "old\n", current: nil).map(\.kind) == [.removed, .removed])
    }

    @Test func displayKeepsTwoLinesOfContextAndFoldsTheRest() {
        let original = (1...9).map(String.init).joined(separator: "\n")
        let current = (1...9).map { $0 == 5 ? "changed" : String($0) }.joined(separator: "\n")

        let display = GitInlineDiff.displayLines(original: original, current: current)

        #expect(display.map(\.text) == ["⋯ 2 unchanged lines folded", "3", "4", "5", "changed", "6", "7", "⋯ 2 unchanged lines folded"])
        #expect(display.map(\.kind) == [.collapsed, .unchanged, .unchanged, .removed, .added, .unchanged, .unchanged, .collapsed])
    }
}
