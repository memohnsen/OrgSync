//
//  SettingsView.swift
//  OrgSync
//
//  Settings tab. GitHub connection plus a Preferences section whose rows push
//  dedicated pages for TODO statuses, notifications, and iOS (Reminders +
//  Calendar) sync. Values persist via `SettingsStore` (plain values in
//  UserDefaults, PAT in the Keychain).
//

import RevenueCatUI
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SubscriptionStore.self) private var subscriptions: SubscriptionStore?
    @AppStorage(NotesLocation.useICloudKey) private var notesInICloud = false
    @State private var migrationError: String?
    @State private var showRelaunchNote = false
    @State private var showProPaywall = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                ConnectRepositoryView()

                Section {
                    NavigationLink {
                        TodoStatesSettingsView(preference: $settings.todoKeywords)
                    } label: {
                        LabeledContent(
                            "Statuses",
                            value:
                                "\(OrgTodoStatusConfiguration.statuses(from: settings.todoKeywords).count)"
                        )
                    }
                    .accessibilityIdentifier("settings.todoStates")
                    .accessibilityHint("Add or delete active and completed TODO statuses.")
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        LabeledContent(
                            "Notifications", value: settings.todoNotifications ? "On" : "Off")
                    }
                    .accessibilityIdentifier("settings.notifications")
                    .accessibilityHint(
                        "Configure local notifications for scheduled and deadline TODOs.")
                    NavigationLink("iOS Sync") {
                        IOSSyncSettingsView()
                    }
                    .accessibilityIdentifier("settings.iosSync")
                    .accessibilityHint("Configure Reminders and Calendar syncing.")
                    Toggle("Archive DONE to done.org", isOn: $settings.archiveCompletedInboxTasks)
                        .accessibilityIdentifier("settings.archiveCompletedInboxTasks")
                    Stepper(
                        "Upcoming agenda: \(settings.agendaDays) days", value: $settings.agendaDays,
                        in: 1...30
                    )
                    .accessibilityIdentifier("settings.agendaDays")
                    .accessibilityHint("Sets how many days appear in the Upcoming agenda.")
                    Picker("Appearance", selection: $settings.appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .accessibilityIdentifier("settings.appearance")
                } header: {
                    Text("Preferences")
                }

                Section {
                    Toggle("Store Notes in iCloud Drive", isOn: $notesInICloud)
                        .accessibilityIdentifier("settings.notesInICloud")
                        .accessibilityHint(
                            "Moves your notes into the app's iCloud Drive folder so they sync across your devices for free."
                        )
                        .onChange(of: notesInICloud) { old, new in
                            guard old != new else { return }
                            migrateNotes(toICloud: new)
                        }
                } header: {
                    Text("Notes Storage")
                } footer: {
                    Text(
                        "In iCloud Drive, your notes sync across your devices through Apple — free, no account with us, no GitHub needed. Takes effect after relaunching OrgSync."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section {
                } footer: {
                    Text("OrgSync • Version \(appVersion)")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 6)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            // iOS 27 draws a solid bar with a hard cutoff on scroll; keep the
            // pre-27 translucent look.
            .toolbarBackground(.hidden, for: .navigationBar)
            .contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("settings.screen")
            .alert(
                "Couldn't Move Notes",
                isPresented: Binding(
                    get: { migrationError != nil },
                    set: { if !$0 { migrationError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { migrationError = nil }
            } message: {
                Text(migrationError ?? "")
            }
            .sheet(isPresented: $showProPaywall) {
                ProPaywallSheet()
            }
            .alert("Notes Moved", isPresented: $showRelaunchNote) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Quit and reopen OrgSync to use the new location.")
            }
        }
    }

    /// Moves the notes directory and reverts the toggle if the move fails.
    private func migrateNotes(toICloud: Bool) {
        Task.detached {
            do {
                try NotesLocation.migrate(toICloud: toICloud)
                await MainActor.run { showRelaunchNote = true }
            } catch {
                await MainActor.run {
                    migrationError =
                        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    notesInICloud = !toICloud
                }
            }
        }
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
