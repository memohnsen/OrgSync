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
}
