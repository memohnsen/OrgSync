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
nonisolated struct SyncRepoState: Codable, Equatable, Sendable {
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
    /// Locally selected paths that will be included in the next commit.
    var stagedPaths: [String]
    /// A Git object created locally through the GitHub API but not yet attached
    /// to the remote branch. This makes Commit and Push distinct operations.
    var pendingCommit: PendingGitCommit?

    init(owner: String,
         repo: String,
         branch: String,
         baseCommitSHA: String,
         files: [String: String] = [:],
         skippedPaths: [String] = [],
         lastSyncDate: Date? = nil,
         stagedPaths: [String] = [],
         pendingCommit: PendingGitCommit? = nil) {
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.baseCommitSHA = baseCommitSHA
        self.files = files
        self.skippedPaths = skippedPaths
        self.lastSyncDate = lastSyncDate
        self.stagedPaths = stagedPaths
        self.pendingCommit = pendingCommit
    }

    private enum CodingKeys: String, CodingKey {
        case owner, repo, branch, baseCommitSHA, files, skippedPaths, lastSyncDate, stagedPaths, pendingCommit
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        owner = try values.decode(String.self, forKey: .owner)
        repo = try values.decode(String.self, forKey: .repo)
        branch = try values.decode(String.self, forKey: .branch)
        baseCommitSHA = try values.decode(String.self, forKey: .baseCommitSHA)
        files = try values.decode([String: String].self, forKey: .files)
        skippedPaths = try values.decodeIfPresent([String].self, forKey: .skippedPaths) ?? []
        lastSyncDate = try values.decodeIfPresent(Date.self, forKey: .lastSyncDate)
        stagedPaths = try values.decodeIfPresent([String].self, forKey: .stagedPaths) ?? []
        pendingCommit = try values.decodeIfPresent(PendingGitCommit.self, forKey: .pendingCommit)
    }
}

/// The exact tree entries represented by a locally committed Git object.
nonisolated struct PendingGitCommit: Codable, Equatable, Sendable {
    struct Change: Codable, Equatable, Sendable {
        var path: String
        /// `nil` represents a deletion.
        var blobSHA: String?
    }

    var sha: String
    var changes: [Change]
}

/// Result of a status check: local working-tree changes plus whether the local
/// baseline differs from the remote branch head.
nonisolated struct SyncStatus: Equatable, Sendable {
    var modified: [String] = []
    var added: [String] = []
    var deleted: [String] = []
    var behind = 0

    var hasLocalChanges: Bool { !modified.isEmpty || !added.isEmpty || !deleted.isEmpty }
    var localChangeCount: Int { modified.count + added.count + deleted.count }
    var changedPaths: [String] { (modified + added + deleted).sorted() }
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
