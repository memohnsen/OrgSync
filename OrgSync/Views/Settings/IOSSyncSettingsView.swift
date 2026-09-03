//
//  IOSSyncSettingsView.swift
//  OrgSync
//
//  Dedicated "iOS Sync" page, pushed from Settings: Reminders and Calendar sync
//  with independent master-source switches, access prompts, manual sync buttons,
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
                    Toggle("iOS Reminders is master", isOn: $settings.remindersMasterSource.isIOSAppsMaster)
                        .accessibilityIdentifier("settings.remindersMasterSource")
                        .accessibilityHint("When on, iOS Reminders is the source of truth. When off, org files are.")
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
                    Toggle("iOS Calendar is master", isOn: $settings.calendarMasterSource.isIOSAppsMaster)
                        .accessibilityIdentifier("settings.calendarMasterSource")
                        .accessibilityHint("When on, iOS Calendar is the source of truth. When off, calendar.org is.")
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
        return String(localized: "When this is off, scheduled and deadline TODOs in your org files update the selected Reminders list.")
    }

    private var calendarFooter: String {
        guard calendar.access == .granted else {
            return String(localized: "Allow access to sync calendar events with calendar.org.")
        }
        return String(localized: "When this is off, events in calendar.org update the OrgSync calendar.")
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
