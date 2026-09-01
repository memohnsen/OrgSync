//
//  QuickAddParserTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct QuickAddParserTests {
    @Test func extractsTagsAndPriorityLeavingCleanTitle() {
        let parsed = QuickAddParser.parse("call Sam #work !!")
        #expect(parsed.title == "call Sam")
        #expect(parsed.tags == ["work"])
        #expect(parsed.priority == "B")
        #expect(parsed.scheduledDate == nil)
    }

    @Test func priorityMarksMapToLevels() {
        #expect(QuickAddParser.parse("a !").priority == "C")
        #expect(QuickAddParser.parse("a !!").priority == "B")
        #expect(QuickAddParser.parse("a !!!").priority == "A")
        #expect(QuickAddParser.parse("a !!!!").priority == nil) // four is not a priority
    }

    @Test func multipleTagsAreDeduplicatedInOrder() {
        let parsed = QuickAddParser.parse("review #a #b #a report")
        #expect(parsed.tags == ["a", "b"])
        #expect(parsed.title == "review report")
    }

    @Test func plainTextHasNoExtraction() {
        let parsed = QuickAddParser.parse("just a plain task")
        #expect(parsed == ParsedQuickAdd(title: "just a plain task", tags: [], priority: nil, scheduledDate: nil, includesTime: false))
    }

    @Test func relativeDayIsExtractedWithoutTime() {
        let parsed = QuickAddParser.parse("buy milk tomorrow")
        #expect(parsed.title == "buy milk")
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let date = try? #require(parsed.scheduledDate)
        #expect(date.map { Calendar.current.isDate($0, inSameDayAs: expected) } == true)
        #expect(parsed.includesTime == false)
    }

    @Test func explicitTimeSetsIncludesTime() {
        let parsed = QuickAddParser.parse("standup at 9am #team")
        #expect(parsed.tags == ["team"])
        #expect(parsed.scheduledDate != nil)
        #expect(parsed.includesTime == true)
    }

    @Test func exclamationInAWordIsNotAPriority() {
        let parsed = QuickAddParser.parse("wow! finish this")
        #expect(parsed.priority == nil)
        #expect(parsed.title == "wow! finish this")
    }
}
