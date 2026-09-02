import Foundation
import Testing
@testable import OrgSync

@Suite struct WidgetAgendaLayoutTests {
    private func todayPlusTasks(_ count: Int) -> [AgendaListLayout.Slot] {
        [.day] + Array(repeating: .task, count: count)
    }

    @Test func mediumWidgetFitsTodayAndFiveTasks() {
        let height = AgendaListLayout.mediumContentHeight
        let packed = AgendaListLayout.packedHeight(dayCount: 1, taskCount: 5)
        #expect(packed <= height)

        let fitted = AgendaListLayout.fitted(
            todayPlusTasks(8),
            in: height,
            dayHeight: AgendaListLayout.dayHeight,
            taskHeight: AgendaListLayout.taskHeight
        )
        #expect(fitted.first == .day)
        #expect(fitted.filter { $0 == .task }.count == 5)
    }

    @Test func extraPaddingDoesNotReduceFiveTaskCapacity() {
        #expect(AgendaListLayout.dayHeaderBottomPadding > 0)
        #expect(AgendaListLayout.listBottomPadding > 0)

        let height = AgendaListLayout.mediumContentHeight
        let fitted = AgendaListLayout.fitted(
            todayPlusTasks(8),
            in: height,
            dayHeight: AgendaListLayout.dayHeight,
            taskHeight: AgendaListLayout.taskHeight
        )
        #expect(fitted.filter { $0 == .task }.count == 5)

        let charged = AgendaListLayout.fitted(
            todayPlusTasks(8),
            in: height - AgendaListLayout.listBottomPadding,
            dayHeight: AgendaListLayout.dayHeight + AgendaListLayout.dayHeaderBottomPadding,
            taskHeight: AgendaListLayout.taskHeight
        )
        #expect(charged.filter { $0 == .task }.count < 5)
    }

    @Test func sixthTaskDoesNotFitMediumContentHeight() {
        let packedSix = AgendaListLayout.packedHeight(dayCount: 1, taskCount: 6)
        #expect(packedSix > AgendaListLayout.mediumContentHeight)
    }

    @Test func trailingDayDividerIsDropped() {
        let fitted = AgendaListLayout.fitted(
            [.day, .task, .day],
            in: AgendaListLayout.packedHeight(dayCount: 1, taskCount: 1) + AgendaListLayout.dayHeight,
            dayHeight: AgendaListLayout.dayHeight,
            taskHeight: AgendaListLayout.taskHeight
        )
        #expect(fitted == [.day, .task])
    }
}
