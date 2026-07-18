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

struct SettingsView: View {
    @Environment(RepoStore.self) private var repo
    @Environment(SettingsStore.self) private var settings
    @Environment(RemindersSyncEngine.self) private var reminders

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                ConnectRepositoryView()

                Section {
                    NavigationLink {
                        TodoStatesSettingsView(preference: $settings.todoKeywords)
                    } label: {
                        LabeledContent("TODO Statuses", value: "\(OrgTodoStatusConfiguration.statuses(from: settings.todoKeywords).count)")
                    }
                    .accessibilityIdentifier("settings.todoStates")
                    .accessibilityHint("Add or delete active and completed TODO statuses.")
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
                    Toggle("Auto-Sync", isOn: $settings.autoSync)
                        .accessibilityIdentifier("settings.autoSync")
                        .accessibilityHint("Enables automatic pull on open and commit and push on close when their individual settings are on.")
                    Toggle("Pull on Open", isOn: $settings.pullOnOpen)
                        .disabled(!settings.autoSync)
                        .accessibilityIdentifier("settings.pullOnOpen")
                        .accessibilityHint("Pulls remote changes when the app becomes active.")
                    Toggle("Commit & Push on Close", isOn: $settings.pushOnClose)
                        .disabled(!settings.autoSync)
                        .accessibilityIdentifier("settings.pushOnClose")
                        .accessibilityHint("Commits and pushes local changes when the app enters the background.")
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Auto-Sync pulls when the app opens and commits & pushes when it closes, each toggleable above. Requires a connected repository.")
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
                        Button("Sync Reminders Now") { Task { await reminders.sync(repo: repo) } }
                            .accessibilityIdentifier("settings.syncRemindersNow")
                    } else {
                        Button("Allow Reminders Access") { Task { await reminders.requestAccess() } }
                            .accessibilityHint("Opens the system permission prompt for Reminders.")
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(reminders.access == .granted ? "Scheduled and deadline TODOs sync two ways with Reminders." : "Allow access to sync scheduled and deadline TODOs with a dedicated OrgSync list.")
                        Text("OrgSync • Version 1.0")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                    }
                }
                if let error = reminders.lastError {
                    Section("Reminders Sync Error") {
                        Text(error).foregroundStyle(.red)
                        Button("Dismiss") { reminders.clearError() }
                    }
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("settings.screen")
        }
    }
}

#Preview {
    let repo = RepoStore()
    let settings = SettingsStore()
    return SettingsView()
        .environment(settings)
        .environment(SyncEngine(repo: repo, settings: settings))
        .environment(OnboardingState())
}
