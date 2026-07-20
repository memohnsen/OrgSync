//
//  SettingsView.swift
//  OrgSync
//
//  Settings tab. GitHub connection plus a Preferences section whose rows push
//  dedicated pages for TODO statuses, notifications, and iOS (Reminders +
//  Calendar) sync. Values persist via `SettingsStore` (plain values in
//  UserDefaults, PAT in the Keychain).
//

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

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
                    NavigationLink("iOS Sync") {
                        IOSSyncSettingsView()
                    }
                    .accessibilityIdentifier("settings.iosSync")
                    .accessibilityHint("Configure Reminders and Calendar syncing.")
                    Toggle("Archive DONE to done.org", isOn: $settings.archiveCompletedInboxTasks)
                        .accessibilityIdentifier("settings.archiveCompletedInboxTasks")
                    Stepper("Upcoming agenda: \(settings.agendaDays) days", value: $settings.agendaDays, in: 1...30)
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
                } footer: {
                    Text("OrgSync • Version \(appVersion)")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
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
