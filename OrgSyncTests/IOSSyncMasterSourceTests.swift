//
//  IOSSyncMasterSourceTests.swift
//  OrgSyncTests
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct IOSSyncMasterSourcePersistenceTests {
    private func makeDefaults() -> UserDefaults {
        let name = "ios-sync-master-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsPreserveExistingIntegrationBehavior() {
        let settings = SettingsStore(defaults: makeDefaults())
        #expect(settings.calendarMasterSource == .iosApps)
        #expect(settings.remindersMasterSource == .iosApps)
    }

    @Test func masterSourcesRoundTripThroughUserDefaults() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.calendarMasterSource = .orgFiles
        settings.remindersMasterSource = .orgFiles

        let restored = SettingsStore(defaults: defaults)
        #expect(restored.calendarMasterSource == .orgFiles)
        #expect(restored.remindersMasterSource == .orgFiles)
    }
}

@Suite struct IOSSyncDirectionPlanningTests {
    @Test func calendarPhasesFollowSelectedMaster() {
        #expect(CalendarSyncRules.calendarPhases(for: .iosApps) == [.importFromIOS])
        #expect(CalendarSyncRules.calendarPhases(for: .orgFiles) == [.exportToIOS])
    }

    @Test func remindersPhasesFollowSelectedMaster() {
        #expect(ReminderSyncRules.syncPhases(for: .iosApps) == [.importFromReminders, .exportToReminders])
        #expect(ReminderSyncRules.syncPhases(for: .orgFiles) == [.exportToReminders])
    }
}
