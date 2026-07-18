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

    @State private var validated: GitHubClient.RepoInfo?
    @State private var branches: [String] = []
    @State private var selectedBranch = ""
    @State private var isWorking = false
    @State private var workingLabel = ""
    @State private var errorMessage: String?
    @State private var showDisconnect = false

    var body: some View {
        Group {
            if sync.isConnected {
                connectedSection
            } else {
                connectFlow
            }
        }
    }

    // MARK: - Connected

    @ViewBuilder
    private var connectedSection: some View {
        Section {
            LabeledContent("Repository", value: sync.connectedRepoName ?? "—")
            LabeledContent("Branch", value: sync.connectedBranch ?? "—")
            if let last = sync.lastSyncDate {
                LabeledContent("Last Synced") {
                    Text(last, format: .relative(presentation: .named))
                }
            } else {
                LabeledContent("Last Synced", value: "Never")
            }
        } header: {
            Text("Connection")
        }

        Section {
            Button(role: .destructive) {
                showDisconnect = true
            } label: {
                Text("Disconnect")
            }
            .accessibilityHint("Stops syncing this repository. You can choose whether to keep local files.")
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
                .accessibilityHint("Fine-grained GitHub Personal Access Token. Stored securely in the Keychain.")
            Button {
                Task { await validate() }
            } label: {
                if isWorking && validated == nil {
                    HStack { ProgressView(); Text("Validating…") }
                } else {
                    Text("Validate Repository")
                }
            }
            .disabled(isWorking || settings.repoURL.isEmpty || settings.token.isEmpty)
            .accessibilityIdentifier("settings.validateRepository")
            .accessibilityHint("Checks the repository URL and Personal Access Token before connecting.")

            if let validated {
                LabeledContent("Repository", value: validated.fullName)
                if let description = validated.description, !description.isEmpty {
                    LabeledContent("About", value: description)
                }
                LabeledContent("Default Branch", value: validated.defaultBranch)
                if !branches.isEmpty {
                    Picker("Branch", selection: $selectedBranch) {
                        ForEach(branches, id: \.self) { Text($0).tag($0) }
                    }
                }
                Button {
                    Task { await connect() }
                } label: {
                    if isWorking {
                        HStack {
                            ProgressView()
                            Text(workingLabel.isEmpty ? "Connecting…" : workingLabel)
                        }
                    } else {
                        Text("Connect & Clone")
                    }
                }
                .disabled(isWorking || selectedBranch.isEmpty)
                .accessibilityIdentifier("settings.connectRepository")
                .accessibilityHint("Downloads the selected branch to this device and enables sync.")
            }
        } header: {
            Text("GitHub")
        } footer: {
            if settings.repoURL.isEmpty || settings.token.isEmpty {
                Text("Paste a fine-grained Personal Access Token with read/write access to the repository. It is stored securely in the Keychain. Enter a repository URL and token to validate it.")
            } else {
                Text("Paste a fine-grained Personal Access Token with read/write access to the repository. It is stored securely in the Keychain.")
            }
        }

        if let errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions

    private func validate() async {
        isWorking = true
        errorMessage = nil
        validated = nil
        defer { isWorking = false }
        do {
            let info = try await sync.validateRepository()
            validated = info
            branches = (try? await sync.availableBranches()) ?? [info.defaultBranch]
            let preferred = settings.branch.isEmpty ? info.defaultBranch : settings.branch
            selectedBranch = branches.contains(preferred) ? preferred : (branches.first ?? info.defaultBranch)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func connect() async {
        isWorking = true
        errorMessage = nil
        workingLabel = "Connecting…"
        defer { isWorking = false }
        do {
            settings.branch = selectedBranch
            try await sync.connect(branch: selectedBranch)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
