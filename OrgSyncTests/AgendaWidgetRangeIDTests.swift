import Testing
@testable import OrgSync

@Suite struct AgendaWidgetRangeIDTests {
    @Test func optionIDsMatchDefaultAndStableRawValues() {
        #expect(AgendaWidgetRangeID.optionIDs == ["today", "week", "upcoming"])
        #expect(AgendaWidgetRangeID.optionIDs.contains(AgendaWidgetRangeID.defaultOptionID))
        #expect(AgendaWidgetRangeID.defaultOptionID == "upcoming")
    }

    @Test func parseAcceptsStableIds() {
        #expect(AgendaWidgetRangeID.parse("today") == .today)
        #expect(AgendaWidgetRangeID.parse("week") == .week)
        #expect(AgendaWidgetRangeID.parse("upcoming") == .upcoming)
        #expect(AgendaWidgetRangeID.parse(" TODAY ") == .today)
    }

    @Test func parseAcceptsLegacyEnglishPickerLabels() {
        #expect(AgendaWidgetRangeID.parse("This Week") == .week)
        #expect(AgendaWidgetRangeID.parse("all upcoming") == .upcoming)
        #expect(AgendaWidgetRangeID.parse("Today") == .today)
    }

    @Test func parseFallsBackToUpcomingForUnknownValues() {
        #expect(AgendaWidgetRangeID.parse("") == .upcoming)
        #expect(AgendaWidgetRangeID.parse("next month") == .upcoming)
    }
}
