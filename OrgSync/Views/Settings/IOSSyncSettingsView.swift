//
//  IOSSyncSettingsView.swift
//  OrgSync
//
//  Dedicated "iOS Sync" page, pushed from Settings: Reminders and Calendar sync
//  with independent master-source pickers, access prompts, manual sync buttons,
//  and error sections.
//

import SwiftUI
import EventKit
import UIKit

struct IOSSyncSettingsView: View {
    @Environment(RepoStore.self) private var repo
    @Environment(SettingsStore.self) private var settings
    @Environment(RemindersSyncEngine.self) private var reminders
    @Environment(CalendarSyncEngine.self) private var calendar
    @Environment(SubscriptionStore.self) private var subscriptions: SubscriptionStore?
    @State private var showRemindersSyncSuccess = false
    @State private var showCalendarSyncSuccess = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            if let subscriptions, !subscriptions.isUnlocked {
                ProLockedSection(feature: .iosSync)
            } else {
                syncSections
            }
        }
        .navigationTitle("iOS Sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Reminders Synced", isPresented: $showRemindersSyncSuccess) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("The selected Reminders list is up to date.")
        }
        .alert("Calendar Synced", isPresented: $showCalendarSyncSuccess) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("calendar.org is up to date.")
        }
    }

    @ViewBuilder
    private var syncSections: some View {
        @Bindable var settings = settings

        Group {
            Section {
                Toggle("Sync with Reminders", isOn: $settings.remindersSync)
                    .disabled(reminders.access != .granted)
                    .accessibilityIdentifier("settings.remindersSync")
                    .accessibilityHint("Synchronizes scheduled and deadline TODOs with the selected Reminders list.")
                if reminders.access == .granted {
                    Picker("Reminders source", selection: $settings.remindersMasterSource) {
                        ForEach(IOSSyncMasterSource.allCases) { source in
                            Text(source.remindersPickerLabel).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.remindersMasterSource")
                    Picker("Reminders List", selection: $settings.remindersListID) {
                        Text("OrgSync (managed)").tag("")
                        ForEach(reminders.lists, id: \.calendarIdentifier) { list in
                            Text(list.title).tag(list.calendarIdentifier)
                        }
                    }
                    .accessibilityIdentifier("settings.remindersList")
                    Button("Sync Reminders Now") { Task { await syncRemindersNow() } }
                        .disabled(!settings.remindersSync || reminders.isSyncing)
                        .accessibilityIdentifier("settings.syncRemindersNow")
                } else {
                    if reminders.access == .denied {
                        Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                            .accessibilityHint("Opens iOS Settings, where you can allow Reminders access for OrgSync.")
                    } else {
                        Button("Allow Reminders Access") { Task { await reminders.requestAccess() } }
                            .accessibilityHint("Opens the system permission prompt for Reminders.")
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text(remindersFooter)
            }
            if let error = reminders.lastError {
                Section("Reminders Sync Error") {
                    Text(error).foregroundStyle(.red)
                    Button("Dismiss") { reminders.clearError() }
                }
            }

            Section {
                Toggle("Sync Calendar", isOn: $settings.calendarSync)
                    .disabled(calendar.access != .granted)
                    .accessibilityIdentifier("settings.calendarSync")
                    .accessibilityHint("Synchronizes calendar events with calendar.org.")
                if calendar.access == .granted {
                    Picker("Calendar source", selection: $settings.calendarMasterSource) {
                        ForEach(IOSSyncMasterSource.allCases) { source in
                            Text(source.calendarPickerLabel).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.calendarMasterSource")
                    Toggle("Show in Agenda & Widgets", isOn: $settings.calendarShowInAgenda)
                        .disabled(!settings.calendarSync)
                        .accessibilityIdentifier("settings.calendarShowInAgenda")
                        .accessibilityHint("Shows or hides mirrored calendar events on the Agenda tab and in widgets.")
                        .onChange(of: settings.calendarShowInAgenda) { _, _ in
                            repo.refresh()
                            AgendaSnapshotWriter.write(repo: repo)
                        }
                    Button("Sync Calendar Now") { Task { await syncCalendarNow() } }
                        .disabled(!settings.calendarSync || calendar.isSyncing)
                        .accessibilityIdentifier("settings.syncCalendarNow")
                } else {
                    if calendar.access == .denied {
                        Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                            .accessibilityHint("Opens iOS Settings, where you can allow Calendar access for OrgSync.")
                    } else {
                        Button("Allow Calendar Access") { Task { await calendar.requestAccess() } }
                            .accessibilityHint("Opens the system permission prompt for Calendars.")
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text(calendarFooter)
            }
            if let error = calendar.lastError {
                Section("Calendar Sync Error") {
                    Text(error).foregroundStyle(.red)
                    Button("Dismiss") { calendar.clearError() }
                }
            }
        }
    }

    private var remindersFooter: String {
        guard reminders.access == .granted else {
            return String(localized: "Allow access to sync scheduled and deadline TODOs with a dedicated OrgSync list.")
        }
        switch settings.remindersMasterSource {
        case .iosApps:
            return String(localized: "When iOS Reminders is the source, Reminders changes import into your org files first, then org TODOs mirror back to the selected list.")
        case .orgFiles:
            return String(localized: "When Org files is the source, scheduled and deadline TODOs in your org files update the selected Reminders list. Reminders-side edits are not imported.")
        }
    }

    private var calendarFooter: String {
        guard calendar.access == .granted else {
            return String(localized: "Allow access to sync calendar events with calendar.org.")
        }
        switch settings.calendarMasterSource {
        case .iosApps:
            return String(localized: "When iOS Calendar is the source, the next 30 days of events are mirrored into calendar.org on every sync. Edits to calendar.org are overwritten.")
        case .orgFiles:
            return String(localized: "When calendar.org is the source, events in that file within the next 30 days update the OrgSync calendar. Calendar-side edits are not imported.")
        }
    }

    private func syncRemindersNow() async {
        await reminders.sync(repo: repo)
        showRemindersSyncSuccess = reminders.lastError == nil
    }

    private func syncCalendarNow() async {
        await calendar.sync(repo: repo)
        showCalendarSyncSuccess = calendar.lastError == nil
    }
}

#Preview {
    let repo = RepoStore()
    let settings = SettingsStore()
    return NavigationStack {
        IOSSyncSettingsView()
            .environment(repo)
            .environment(settings)
            .environment(RemindersSyncEngine(settings: settings))
            .environment(CalendarSyncEngine(settings: settings))
    }
}
