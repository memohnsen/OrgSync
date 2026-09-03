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

    @Test func switchBindingMapsOnToIOSAppsAndOffToOrgFiles() {
        var source = IOSSyncMasterSource.iosApps
        #expect(source.isIOSAppsMaster)
        source.isIOSAppsMaster = false
        #expect(source == .orgFiles)
        source.isIOSAppsMaster = true
        #expect(source == .iosApps)
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

    @Test func staleMappingKeysSnapshotBeforeDeletion() {
        let mappings = ["id|live": "R-1", "id|gone": "R-2"]
        #expect(ReminderSyncRules.staleMappingKeys(liveKeys: ["id|live"], mappings: mappings) == ["id|gone"])
    }

    @Test func mappedDeletionCandidatesExcludeUnmappedPersonalReminders() {
        let mappings = ["id|org-task": "R-MANAGED"]
        let listIDs: Set<String> = ["R-MANAGED", "R-PERSONAL"]
        let stale = ReminderSyncRules.staleMappingKeys(liveKeys: ["id|org-task"], mappings: mappings)
        let deletions = ReminderSyncRules.mappedDeletionReminderIDs(mappings: mappings, staleKeys: stale)
        let unmapped = ReminderSyncRules.unmappedReminderIDs(inList: listIDs, mappings: mappings)
        #expect(deletions.isEmpty)
        #expect(unmapped == ["R-PERSONAL"])
        #expect(deletions.contains("R-PERSONAL") == false)
    }

    @Test func mappedDeletionCandidatesIncludeRemovedOrgEntries() {
        let mappings = ["id|deleted": "R-OLD", "id|kept": "R-KEEP"]
        let stale = ReminderSyncRules.staleMappingKeys(liveKeys: ["id|kept"], mappings: mappings)
        let deletions = ReminderSyncRules.mappedDeletionReminderIDs(mappings: mappings, staleKeys: stale)
        #expect(deletions == ["R-OLD"])
        #expect(deletions.contains("R-KEEP") == false)
    }
}
