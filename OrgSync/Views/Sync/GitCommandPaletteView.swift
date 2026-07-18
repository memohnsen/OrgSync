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
    @State private var showDiscardChangesPrompt = false
    @State private var showChanges = false
    @State private var showCommitLog = false

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
                        LabeledContent("Local Changes", value: "\(sync.status.localChangeCount)")
                        LabeledContent("Staged", value: "\(sync.stagedChangeCount)")
                        Button { showChanges = true } label: {
                            Text("View Changes").foregroundStyle(canViewChanges ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canViewChanges)
                        .accessibilityHint("Shows local additions, edits, and deletions compared with the last synced version.")
                        Button { showCommitLog = true } label: {
                            Text("Commit Log").foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows recent commits on the connected branch.")
                    }

                    Section("Commands") {
                        Button {
                            Task { await sync.pullNow(); repo.refresh() }
                        } label: {
                            commandLabel("Pull", systemImage: "arrow.down.circle", enabled: canPull, isLoading: isRunning("Pulling…"))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canPull)
                        .accessibilityHint(sync.hasPendingCommit ? "Push the pending commit before pulling." : "Downloads and merges remote changes.")

                        Button {
                            Task { await sync.stageAllNow() }
                        } label: {
                            commandLabel("Stage All Changes", systemImage: "tray.and.arrow.down", enabled: canStage, isLoading: isRunning("Staging…"))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canStage)
                        .accessibilityHint("Selects every current local change for the next commit.")

                        Button(role: .destructive) {
                            showDiscardChangesPrompt = true
                        } label: {
                            commandLabel("Discard Local Changes", systemImage: "arrow.uturn.backward", enabled: canDiscardChanges, isLoading: isRunning("Discarding changes…"))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canDiscardChanges)
                        .accessibilityHint("Restores the working copy to the last synced version. This cannot be undone.")

                        Button {
                            commitMessage = OrgSyncCommitMessage.automatic()
                            showCommitPrompt = true
                        } label: {
                            commandLabel("Commit Staged Changes", systemImage: "checkmark.seal", enabled: canCommit, isLoading: isRunning("Committing…"))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCommit)
                        .accessibilityHint("Creates a local pending Git commit without publishing it.")

                        Button {
                            Task { await sync.pushPendingNow(); await reminders.sync(repo: repo); repo.refresh() }
                        } label: {
                            commandLabel("Push", systemImage: "arrow.up.circle", enabled: canPush, isLoading: isRunning("Pushing…"))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canPush)
                        .accessibilityHint("Publishes the pending commit to GitHub.")

                        Button(role: .destructive) {
                            showDiscardPrompt = true
                        } label: {
                            commandLabel("Discard Pending Commit", systemImage: "xmark.seal", enabled: canDiscard, isLoading: isRunning("Discarding…"))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canDiscard)
                        .accessibilityHint("Abandons the pending commit. Your file changes are kept as local changes.")

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
            .confirmationDialog("Discard Local Changes?", isPresented: $showDiscardChangesPrompt, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) {
                    Task { await sync.discardLocalChangesNow(); repo.refresh() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This restores modified and deleted files from the last synced commit and removes newly added files. This cannot be undone.")
            }
            .sheet(isPresented: $showChanges) { GitChangesView() }
            .sheet(isPresented: $showCommitLog) {
                NavigationStack {
                    CommitLogView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showCommitLog = false }
                            }
                        }
                }
            }
        }
        .accessibilityIdentifier("git.commandPalette")
    }

    private var canPull: Bool { !sync.phase.isBusy && !sync.hasPendingCommit }
    private var canViewChanges: Bool { !sync.phase.isBusy && sync.status.hasLocalChanges }
    private var canStage: Bool { !sync.phase.isBusy && !sync.hasPendingCommit && sync.status.hasLocalChanges }
    private var canDiscardChanges: Bool { !sync.phase.isBusy && !sync.hasPendingCommit && sync.status.hasLocalChanges }
    private var canCommit: Bool { !sync.phase.isBusy && !sync.hasPendingCommit && sync.stagedChangeCount > 0 }
    private var canPush: Bool { !sync.phase.isBusy && sync.hasPendingCommit }
    private var canDiscard: Bool { !sync.phase.isBusy && sync.hasPendingCommit }
    private func isRunning(_ message: String) -> Bool {
        if case let .syncing(currentMessage) = sync.phase {
            return currentMessage == message
        }
        return false
    }

    private func commandLabel(_ title: String, systemImage: String, enabled: Bool, isLoading: Bool = false) -> some View {
        HStack(spacing: 8) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.accentColor)
                } else {
                    Image(systemName: systemImage)
                        .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                }
            }
            .frame(width: 24)
            Text(isLoading ? loadingTitle(for: title) : title)
                .foregroundStyle(isLoading || enabled ? Color.primary : Color.secondary)
        }
    }

    private func loadingTitle(for title: String) -> String {
        switch title {
        case "Stage All Changes": "Staging…"
        case "Commit Staged Changes": "Committing…"
        case "Discard Local Changes": "Discarding changes…"
        case "Discard Pending Commit": "Discarding…"
        default: "\(title)ing…"
        }
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
