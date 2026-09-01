import Testing
import OrgSyncIntents

@Suite struct AgendaWidgetRangeTests {
    @Test func appEnumCasesAreTheFixedEditWidgetSet() {
        #expect(AgendaWidgetRange.allCases.map(\.rawValue) == ["today", "week", "upcoming"])
        #expect(AgendaWidgetRange.caseDisplayRepresentations.keys.count == AgendaWidgetRange.allCases.count)
    }

    @Test func configurationIntentDefaultsToUpcoming() {
        #expect(UpcomingConfigIntent().range == .upcoming)
        #expect(UpcomingConfigIntent(range: .today).range == .today)
        #expect(UpcomingConfigIntent(range: .week).range == .week)
    }
}
