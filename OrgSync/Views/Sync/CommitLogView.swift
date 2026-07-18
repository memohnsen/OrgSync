//
//  CommitLogView.swift
//  OrgSync
//
//  Recent commits on the connected branch, fetched from the GitHub commit list
//  API. Reachable from the Git Commands page.
//

import SwiftUI

struct CommitLogView: View {
    @Environment(SyncEngine.self) private var sync

    @State private var commits: [CommitSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading commits…")
                        .foregroundStyle(.secondary)
                }
            } else if let loadError {
                ContentUnavailableView("Couldn't Load Commits", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else if commits.isEmpty {
                ContentUnavailableView("No Commits", systemImage: "clock",
                                       description: Text("This branch has no commit history yet."))
            } else {
                ForEach(commits) { commit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commit.title)
                            .font(.body)
                        HStack(spacing: 6) {
                            Text(commit.authorName)
                            Text("·")
                            Text(commit.date, format: .relative(presentation: .named))
                            Spacer()
                            Text(commit.shortSHA)
                                .monospaced()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(commit.title), by \(commit.authorName), \(commit.date.formatted(.relative(presentation: .named))), commit \(commit.shortSHA)")
                }
            }
        }
        .navigationTitle("Commit Log")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = commits.isEmpty
        loadError = nil
        do {
            commits = try await sync.recentCommits()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
