//
//  GitCommandPaletteView.swift
//  OrgSync
//
//  A compact, explicit Git workflow over OrgSync's GitHub API backend.
//

import SwiftUI

struct GitCommandPaletteView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(RepoStore.self) private var repo
    @Environment(RemindersSyncEngine.self) private var reminders
    @Environment(\.dismiss) private var dismiss

    @State private var commitMessage = ""
    @State private var showCommitPrompt = false
    @State private var showDiscardPrompt = false

    var body: some View {
        NavigationStack {
            List {
                if !sync.isConnected {
                    ContentUnavailableView(
                        "Connect a Repository",
                        systemImage: "arrow.triangle.branch",
                        description: Text("Configure GitHub in Settings before using Git commands.")
                    )
                } else {
                    Section("Repository") {
                        LabeledContent("Branch", value: sync.connectedBranch ?? "—")
                        LabeledContent("Local Changes", value: "\(sync.status.localChangeCount)")
                        LabeledContent("Staged", value: "\(sync.stagedChangeCount)")
                        LabeledContent("Pending Commit", value: sync.pendingCommitSHA ?? "None")
                    }

                    Section("Commands") {
                        Button {
                            Task { await sync.pullNow(); repo.refresh() }
                        } label: {
                            Label("Pull", systemImage: "arrow.down.circle")
                        }
                        .disabled(sync.phase.isBusy || sync.hasPendingCommit)
                        .accessibilityHint(sync.hasPendingCommit ? "Push the pending commit before pulling." : "Downloads and merges remote changes.")

                        Button {
                            Task { await sync.stageAllNow() }
                        } label: {
                            Label("Stage All Changes", systemImage: "tray.and.arrow.down")
                        }
                        .disabled(sync.phase.isBusy || sync.hasPendingCommit || !sync.status.hasLocalChanges)
                        .accessibilityHint("Selects every current local change for the next commit.")

                        Button {
                            commitMessage = OrgSyncCommitMessage.automatic()
                            showCommitPrompt = true
                        } label: {
                            Label("Commit Staged Changes", systemImage: "checkmark.seal")
                        }
                        .disabled(sync.phase.isBusy || sync.hasPendingCommit || sync.stagedChangeCount == 0)
                        .accessibilityHint("Creates a local pending Git commit without publishing it.")

                        Button {
                            Task { await sync.pushPendingNow(); await reminders.sync(repo: repo); repo.refresh() }
                        } label: {
                            Label("Push", systemImage: "arrow.up.circle")
                        }
                        .disabled(sync.phase.isBusy || !sync.hasPendingCommit)
                        .accessibilityHint("Publishes the pending commit to GitHub.")

                        Button(role: .destructive) {
                            showDiscardPrompt = true
                        } label: {
                            Label("Discard Pending Commit", systemImage: "xmark.seal")
                        }
                        .disabled(sync.phase.isBusy || !sync.hasPendingCommit)
                        .accessibilityHint("Abandons the pending commit. Your file changes are kept as local changes.")

                        Button {
                            Task { await sync.syncNow(); await reminders.sync(repo: repo); repo.refresh() }
                        } label: {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(sync.phase.isBusy || sync.hasPendingCommit)
                        .accessibilityHint("Pulls remote changes, then commits and pushes local changes.")
                    }

                    let conflicts = sync.conflictCopies()
                    if !conflicts.isEmpty {
                        Section("Conflicts") {
                            NavigationLink {
                                ConflictResolutionView()
                            } label: {
                                Label("Resolve \(conflicts.count) Conflict\(conflicts.count == 1 ? "" : "s")",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .accessibilityHint("Choose the local or remote version for each conflicted file. Pushing is blocked until all conflicts are resolved.")
                        }
                    }

                    if case let .syncing(message) = sync.phase {
                        Section {
                            HStack { ProgressView(); Text(message) }
                        }
                    }
                    if let error = sync.lastError {
                        Section("Git Error") {
                            Text(error).foregroundStyle(.red)
                            Button("Dismiss Error") { sync.lastError = nil }
                        }
                    }
                }
            }
            .navigationTitle("Git Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard sync.isConnected else { return }
                _ = try? await sync.refreshStatus()
            }
            .alert("Commit Staged Changes", isPresented: $showCommitPrompt) {
                TextField("Commit message", text: $commitMessage)
                Button("Cancel", role: .cancel) {}
                Button("Commit") {
                    let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await sync.commitStagedNow(message: message.isEmpty ? nil : message) }
                }
            } message: {
                Text("This creates a local pending commit. Use Push when you are ready to publish it to GitHub.")
            }
            .confirmationDialog("Discard Pending Commit?", isPresented: $showDiscardPrompt, titleVisibility: .visible) {
                Button("Discard Commit", role: .destructive) {
                    Task { await sync.discardPendingCommitNow() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The unpublished commit is abandoned. Your file changes stay in the working copy as local changes, so you can pull and commit again.")
            }
        }
        .accessibilityIdentifier("git.commandPalette")
    }
}

#Preview {
    let repo = RepoStore()
    let settings = SettingsStore()
    GitCommandPaletteView()
        .environment(repo)
        .environment(SyncEngine(repo: repo, settings: settings))
        .environment(RemindersSyncEngine(settings: settings))
}
