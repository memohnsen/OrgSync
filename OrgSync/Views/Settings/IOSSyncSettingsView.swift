//
//  IOSSyncSettingsView.swift
//  OrgSync
//
//  Dedicated "iOS Sync" page, pushed from Settings: two-way Reminders sync and
//  the read-only Calendar mirror, including their access prompts, manual sync
//  buttons, and error sections.
//

import SwiftUI
import EventKit
import UIKit

struct IOSSyncSettingsView: View {
    @Environment(RepoStore.self) private var repo
    @Environment(SettingsStore.self) private var settings
    @Environment(RemindersSyncEngine.self) private var reminders
    @Environment(CalendarSyncEngine.self) private var calendar
    @State private var showRemindersSyncSuccess = false
    @State private var showCalendarSyncSuccess = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Sync with Reminders", isOn: $settings.remindersSync)
                    .disabled(reminders.access != .granted)
                    .accessibilityIdentifier("settings.remindersSync")
                    .accessibilityHint("Synchronizes scheduled and deadline TODOs with the selected Reminders list.")
                if reminders.access == .granted {
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
                Text(reminders.access == .granted ? "Scheduled and deadline TODOs sync two ways with only the selected Reminders list." : "Allow access to sync scheduled and deadline TODOs with a dedicated OrgSync list.")
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
                    .accessibilityHint("Mirrors upcoming calendar events into a read-only calendar.org note.")
                if calendar.access == .granted {
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
                Text("The next \(CalendarSyncRules.windowDays) days of events are mirrored into calendar.org on every app open. The file is read-only: edits to it are overwritten.")
            }
            if let error = calendar.lastError {
                Section("Calendar Sync Error") {
                    Text(error).foregroundStyle(.red)
                    Button("Dismiss") { calendar.clearError() }
                }
            }
        }
        .navigationTitle("iOS Sync")
        .navigationBarTitleDisplayMode(.inline)
        // iOS 27 draws a solid bar with a hard cutoff on scroll; keep the
        // pre-27 translucent look.
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
