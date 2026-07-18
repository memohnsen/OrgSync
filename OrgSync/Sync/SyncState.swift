//
//  SyncState.swift
//  OrgSync
//
//  Persisted sync bookkeeping and the value types the sync UI observes.
//
//  `SyncRepoState` is the on-disk record (`Documents/repo/.orgsync/state.json`)
//  that lets the engine diff the working copy against a known baseline without
//  a full git object store: it remembers the connected repo, the branch, the
//  commit the working copy was last aligned to, and the git blob SHA of every
//  file at that baseline.
//

import Foundation

/// On-disk sync baseline. Codable so it round-trips to `state.json`.
struct SyncRepoState: Codable, Equatable {
    var owner: String
    var repo: String
    var branch: String
    /// Commit the working copy is aligned to (the merge base for the next pull).
    var baseCommitSHA: String
    /// Repo-relative path -> git blob SHA at the baseline commit.
    var files: [String: String]
    /// Paths recorded in the tree but not downloaded (large binaries), so a
    /// subsequent status doesn't mistake them for local deletions.
    var skippedPaths: [String]
    var lastSyncDate: Date?

    init(owner: String,
         repo: String,
         branch: String,
         baseCommitSHA: String,
         files: [String: String] = [:],
         skippedPaths: [String] = [],
         lastSyncDate: Date? = nil) {
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.baseCommitSHA = baseCommitSHA
        self.files = files
        self.skippedPaths = skippedPaths
        self.lastSyncDate = lastSyncDate
    }
}

/// Result of a status check: local working-tree changes plus whether the local
/// baseline differs from the remote branch head.
struct SyncStatus: Equatable {
    var modified: [String] = []
    var added: [String] = []
    var deleted: [String] = []
    var behind = 0

    var hasLocalChanges: Bool { !modified.isEmpty || !added.isEmpty || !deleted.isEmpty }
    var localChangeCount: Int { modified.count + added.count + deleted.count }
}

/// A commit as shown in the log view.
struct CommitSummary: Identifiable, Equatable {
    let sha: String
    let message: String
    let authorName: String
    let date: Date

    var id: String { sha }
    var shortSHA: String { String(sha.prefix(7)) }
    /// First line of the commit message.
    var title: String { message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message }
}
