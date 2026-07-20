//
//  SettingsView.swift
//  OrgSync
//
//  Settings tab. A native Form grouped into GitHub connection, Sync
//  preferences, and Reminders. Values persist via `SettingsStore` (plain values
//  in UserDefaults, PAT in the Keychain). No network calls happen yet — later
//  phases consume these settings.
//

import SwiftUI
import EventKit
import UIKit

struct SettingsView: View {
    @Environment(RepoStore.self) private var repo
    @Environment(SettingsStore.self) private var settings
    @Environment(RemindersSyncEngine.self) private var reminders
    @Environment(CalendarSyncEngine.self) private var calendar
    @State private var showRemindersSyncSuccess = false
    @State private var showCalendarSyncSuccess = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                ConnectRepositoryView()

                Section {
                    NavigationLink {
                        TodoStatesSettingsView(preference: $settings.todoKeywords)
                    } label: {
                        LabeledContent("Statuses", value: "\(OrgTodoStatusConfiguration.statuses(from: settings.todoKeywords).count)")
                    }
                    .accessibilityIdentifier("settings.todoStates")
                    .accessibilityHint("Add or delete active and completed TODO statuses.")
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        LabeledContent("Notifications", value: settings.todoNotifications ? "On" : "Off")
                    }
                    .accessibilityIdentifier("settings.notifications")
                    .accessibilityHint("Configure local notifications for scheduled and deadline TODOs.")
                    Stepper("Upcoming agenda: \(settings.agendaDays) days", value: $settings.agendaDays, in: 1...30)
                        .accessibilityIdentifier("settings.agendaDays")
                        .accessibilityHint("Sets how many days appear in the Upcoming agenda.")
                    Picker("Appearance", selection: $settings.appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .accessibilityIdentifier("settings.appearance")
                } header: { Text("Preferences") }

                Section {
                    Toggle("Archive completed tasks", isOn: $settings.archiveCompletedInboxTasks)
                        .accessibilityIdentifier("settings.archiveCompletedInboxTasks")
                        .accessibilityHint("Moves completed, non-recurring tasks from inbox.org to done.org.")
                } header: {
                    Text("Inbox")
                } footer: {
                    Text("Recurring tasks remain in inbox.org and advance to their next scheduled occurrence.")
                }

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
                    VStack(alignment: .leading, spacing: 14) {
                        Text("The next \(CalendarSyncRules.windowDays) days of events are mirrored into calendar.org on every app open. The file is read-only: edits to it are overwritten.")
                        Text("OrgSync • Version \(appVersion)")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                    }
                }
                if let error = calendar.lastError {
                    Section("Calendar Sync Error") {
                        Text(error).foregroundStyle(.red)
                        Button("Dismiss") { calendar.clearError() }
                    }
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            // iOS 27 draws a solid bar with a hard cutoff on scroll; keep the
            // pre-27 translucent look.
            .toolbarBackground(.hidden, for: .navigationBar)
            .contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("settings.screen")
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
    }

    private func syncRemindersNow() async {
        await reminders.sync(repo: repo)
        showRemindersSyncSuccess = reminders.lastError == nil
    }

    private func syncCalendarNow() async {
        await calendar.sync(repo: repo)
        showCalendarSyncSuccess = calendar.lastError == nil
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

#Preview {
    let repo = RepoStore()
    let settings = SettingsStore()
    return SettingsView()
        .environment(settings)
        .environment(SyncEngine(repo: repo, settings: settings))
        .environment(RemindersSyncEngine(settings: settings))
        .environment(CalendarSyncEngine(settings: settings))
        .environment(OnboardingState())
}
