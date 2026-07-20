//
//  ConnectRepositoryView.swift
//  OrgSync
//
//  The connect-repository flow used inside Settings: validate the entered repo +
//  token, choose a branch, and run the initial clone. When already connected it
//  shows connection status and a disconnect option.
//

import SwiftUI

struct ConnectRepositoryView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(SettingsStore.self) private var settings
    @Environment(SubscriptionStore.self) private var subscriptions: SubscriptionStore?

    @State private var isWorking = false
    @State private var workingLabel = ""
    @State private var errorMessage: String?
    @State private var showDisconnect = false

    var body: some View {
        Group {
            if sync.isConnected {
                // An existing connection keeps working even without Pro — a
                // lapsed subscription must never strand notes mid-sync.
                connectedSection
            } else if let subscriptions, !subscriptions.isUnlocked {
                ProLockedSection(feature: .githubSync)
            } else {
                connectFlow
            }
        }
    }

    // MARK: - Connected

    @ViewBuilder
    private var connectedSection: some View {
        @Bindable var settings = settings
        Section {
            LabeledContent("Repository", value: sync.connectedRepoName ?? "—")
            LabeledContent("Branch", value: sync.connectedBranch ?? "—")
            Toggle("Git Pull on Open", isOn: $settings.pullOnOpen)
                .accessibilityIdentifier("settings.pullOnOpen")
                .accessibilityHint("Pulls remote changes when the app becomes active.")
            Button(role: .destructive) {
                showDisconnect = true
            } label: {
                Text("Disconnect")
            }
            .accessibilityHint("Stops syncing this repository. You can choose whether to keep local files.")
        } header: {
            Text("Connection")
        }
        .confirmationDialog("Disconnect Repository", isPresented: $showDisconnect, titleVisibility: .visible) {
            Button("Keep Local Files", role: .none) { Task { await sync.disconnect(deleteLocalFiles: false) } }
            Button("Delete Local Files", role: .destructive) { Task { await sync.disconnect(deleteLocalFiles: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stop syncing with GitHub. You can keep the downloaded notes on this device or remove them.")
        }
    }

    // MARK: - Connect flow

    @ViewBuilder
    private var connectFlow: some View {
        @Bindable var settings = settings
        Section {
            TextField("Repository URL", text: $settings.repoURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("settings.repositoryURL")
                .accessibilityLabel("Repository URL")
                .accessibilityHint("GitHub HTTPS repository URL.")
            TextField("Branch", text: $settings.branch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.branch")
                .accessibilityLabel("Branch")
                .accessibilityHint("Git branch to sync.")
            SecureField("Personal Access Token", text: $settings.token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.personalAccessToken")
                .accessibilityLabel("Personal Access Token")
                .accessibilityHint("Fine-grained GitHub Personal Access Token with Contents permission set to Read and write for this repository.")

            Button {
                Task { await connect() }
            } label: {
                if isWorking {
                    HStack {
                        ProgressView()
                        Text(workingLabel)
                    }
                } else {
                    Text("Connect & Clone")
                }
            }
            .disabled(isWorking || settings.repoURL.isEmpty || settings.token.isEmpty)
            .accessibilityIdentifier("settings.connectRepository")
            .accessibilityHint("Validates the repository, then downloads its selected branch to this device.")

        } header: {
            Text("GitHub")
        } footer: {
            Text("Fine-grained PAT required: Contents permission set to Read and write for this repository.")
        }

        if let errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions

    private func connect() async {
        isWorking = true
        errorMessage = nil
        workingLabel = "Validating…"
        defer { isWorking = false }
        do {
            let info = try await sync.validateRepository()
            let branch = settings.branch.isEmpty ? info.defaultBranch : settings.branch
            workingLabel = "Connecting…"
            settings.branch = branch
            try await sync.connect(branch: branch)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
