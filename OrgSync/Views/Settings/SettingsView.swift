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
    @Environment(SyncEngine.self) private var sync
    @Environment(RemindersSyncEngine.self) private var reminders
    @Environment(OnboardingState.self) private var onboarding

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    TextField("Repository URL", text: $settings.repoURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(sync.isConnected)
                        .accessibilityIdentifier("settings.repositoryURL")
                        .accessibilityLabel("Repository URL")
                        .accessibilityHint("GitHub HTTPS repository URL. Disabled while connected.")
                    TextField("Branch", text: $settings.branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(sync.isConnected)
                        .accessibilityIdentifier("settings.branch")
                        .accessibilityLabel("Branch")
                        .accessibilityHint("Git branch to sync. Disabled while connected.")
                    SecureField("Personal Access Token", text: $settings.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.personalAccessToken")
                        .accessibilityLabel("Personal Access Token")
                        .accessibilityHint("Fine-grained GitHub Personal Access Token. Stored securely in the Keychain.")
                } header: {
                    Text("GitHub")
                } footer: {
                    Text("Paste a fine-grained Personal Access Token with read/write access to the repository. It is stored securely in the Keychain.")
                }

                Section {
                    TextField("TODO keywords", text: $settings.todoKeywords)
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("settings.todoKeywords")
                        .accessibilityLabel("TODO keywords")
                    Stepper("Upcoming agenda: \(settings.agendaDays) days", value: $settings.agendaDays, in: 1...30)
                        .accessibilityIdentifier("settings.agendaDays")
                        .accessibilityHint("Sets how many days appear in the Upcoming agenda.")
                    Picker("Appearance", selection: $settings.appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .accessibilityIdentifier("settings.appearance")
                } header: { Text("Preferences") } footer: {
                    Text("Default: “TODO PROGRESS WAITING | DONE”. Add your own statuses with org syntax; each gets a color automatically.")
                }

                ConnectRepositoryView()

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

                if sync.isConnected {
                    Section("Sync Health") {
                        LabeledContent("Local Changes", value: "\(sync.status.localChangeCount)")
                        LabeledContent("Remote Updates", value: sync.status.behind == 0 ? "Up to date" : "Available")
                        if let last = sync.lastSyncDate {
                            LabeledContent("Last Sync") { Text(last, format: .relative(presentation: .named)) }
                        }
                        Button("Refresh Sync Status") { Task { _ = try? await sync.refreshStatus() } }
                    }
                }

                Section("About") {
                    LabeledContent("OrgSync", value: "Version 1.0")
                    Text("Local-first org notes, GitHub sync, Agenda, widgets, and Reminders.")
                        .font(.footnote).foregroundStyle(.secondary)
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
                    Text(reminders.access == .granted ? "Scheduled and deadline TODOs sync two ways with Reminders." : "Allow access to sync scheduled and deadline TODOs with a dedicated OrgSync list.")
                }
                if let error = reminders.lastError {
                    Section("Reminders Sync Error") {
                        Text(error).foregroundStyle(.red)
                        Button("Dismiss") { reminders.clearError() }
                    }
                }

                #if DEBUG
                Section("Developer") {
                    Button("Restart Onboarding") {
                        onboarding.restart()
                    }
                    .accessibilityIdentifier("settings.restartOnboarding")
                    .accessibilityHint("Shows the first-run onboarding flow again.")
                }
                #endif
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
