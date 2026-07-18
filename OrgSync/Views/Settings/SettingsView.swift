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

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    TextField("Repository URL", text: $settings.repoURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Branch", text: $settings.branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Personal Access Token", text: $settings.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("GitHub")
                } footer: {
                    Text("Paste a fine-grained Personal Access Token with read/write access to the repository. It is stored securely in the Keychain.")
                }

                Section {
                    Toggle("Auto-Sync", isOn: $settings.autoSync)
                    Toggle("Pull on Open", isOn: $settings.pullOnOpen)
                    Toggle("Commit & Push on Close", isOn: $settings.pushOnClose)
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Sync is not active yet. These preferences are saved for when GitHub sync is enabled.")
                }

                Section {
                    Toggle("Sync with Reminders", isOn: $settings.remindersSync)
                        .disabled(true)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Two-way Reminders sync is coming in a later update.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(SettingsStore())
}
