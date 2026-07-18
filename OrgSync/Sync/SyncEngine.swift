//
//  SyncEngine.swift
//  OrgSync
//
//  Orchestrates the local working copy (Documents/repo) against a GitHub branch
//  using `GitHubClient` and the `.orgsync/state.json` baseline. It implements a
//  git-like clone / status / pull / push without a local object store: the
//  baseline blob SHAs recorded in state, plus locally-computed git blob SHAs of
//  the working files, are enough to detect three-way changes and drive merges.
//
//  Observable so SwiftUI can reflect the current phase, last-synced time, and
//  ahead/behind counts. Errors from user-driven runs are captured into
//  `lastError` for native alert presentation.
//

import Foundation
import Observation

@MainActor
@Observable
final class SyncEngine {
    enum Phase: Equatable {
        case idle
        case syncing(String)
        case error(String)

        var isBusy: Bool { if case .syncing = self { return true } else { return false } }
    }

    private(set) var phase: Phase = .idle
    private(set) var status = SyncStatus()
    private(set) var lastSyncDate: Date?
    /// Surfaced to the UI as an alert; cleared by the view once shown.
    var lastError: String?

    var isConnected: Bool { state != nil }
    var connectedRepoName: String? { state.map { "\($0.owner)/\($0.repo)" } }
    var connectedBranch: String? { state?.branch }

    private let repo: RepoStore
    private let settings: SettingsStore
    private var state: SyncRepoState? {
        didSet { lastSyncDate = state?.lastSyncDate }
    }

    /// Files larger than this are recorded in state but not downloaded on clone.
    private let maxBlobDownloadBytes = 5 * 1024 * 1024

    private let fileManager = FileManager.default

    init(repo: RepoStore, settings: SettingsStore) {
        self.repo = repo
        self.settings = settings
        self.state = Self.loadState(from: Self.stateURL(repoRoot: repo.repoURL))
        self.lastSyncDate = state?.lastSyncDate
    }

    // MARK: - User-driven wrappers (non-throwing; surface errors as alerts)

    func syncNow() async { await run("Syncing…") { try await self.sync() } }
    func pullNow() async { await run("Pulling…") { try await self.pull() } }
    func pushNow(message: String? = nil) async { await run("Pushing…") { try await self.commitAndPush(message: message) } }

    private func run(_ label: String, _ op: @escaping () async throws -> Void) async {
        phase = .syncing(label)
        do {
            try await op()
            phase = .idle
        } catch {
            phase = .error(message(for: error))
            lastError = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Validation / connect

    func validateRepository() async throws -> GitHubClient.RepoInfo {
        let client = try makeClientFromSettings()
        return try await client.getRepo()
    }

    func availableBranches() async throws -> [String] {
        let client = try makeClientFromSettings()
        return try await client.listBranches().map(\.name)
    }

    /// Initial clone: validate, fetch the tree at the branch head, download text
    /// blobs, and write the working copy. Seeded sample files are backed up once
    /// to `Documents/pre-sync-backup` before being replaced.
    func connect(branch: String) async throws {
        let client = try makeClientFromSettings()
        let info = try await client.getRepo()
        let (owner, repoName) = (client.owner, client.repo)

        phase = .syncing("Fetching \(info.name)…")
        let head = try await client.getRef(branch: branch).object.sha
        let commit = try await client.getCommit(sha: head)
        let tree = try await client.getTree(sha: commit.tree.sha, recursive: true)
        guard !tree.truncated else {
            throw GitHubError.decoding("repository tree is too large for a safe initial clone")
        }
        let blobs = tree.tree.filter { $0.type == "blob" }

        let hasLocalFiles = !enumerateWorkingFiles().isEmpty
        if !blobs.isEmpty && hasLocalFiles {
            backupWorkingCopyOnce()
            clearWorkingCopy()
        }

        var files: [String: String] = [:]
        var skipped: [String] = []
        var count = 0
        for entry in blobs {
            count += 1
            files[entry.path] = entry.sha
            if let size = entry.size, size > maxBlobDownloadBytes {
                skipped.append(entry.path)
                continue
            }
            phase = .syncing("Downloading \(count)/\(blobs.count)…")
            let data = try await client.getBlobData(sha: entry.sha)
            try writeWorkingFile(path: entry.path, data: data)
        }

        var newState = SyncRepoState(owner: owner, repo: repoName, branch: branch,
                                     baseCommitSHA: head, files: files, skippedPaths: skipped)
        newState.lastSyncDate = Date()
        persist(newState)
        repo.refresh()
        status = try await computeStatus(using: client, state: newState)
    }

    /// Clears sync bookkeeping. Optionally removes the local working files too;
    /// otherwise they are left in place (now un-tracked).
    func disconnect(deleteLocalFiles: Bool) {
        if deleteLocalFiles {
            clearWorkingCopy()
            repo.refresh()
        }
        try? fileManager.removeItem(at: Self.stateURL(repoRoot: repo.repoURL))
        state = nil
        status = SyncStatus()
        phase = .idle
    }

    // MARK: - Status

    @discardableResult
    func refreshStatus() async throws -> SyncStatus {
        guard let state else { throw GitHubError.notConfigured }
        let client = try makeClient(for: state)
        let result = try await computeStatus(using: client, state: state)
        status = result
        return result
    }

    private func computeStatus(using client: GitHubClient, state: SyncRepoState) async throws -> SyncStatus {
        var summary = localChanges(against: state)
        // Ahead/behind: compare the recorded head against the current remote head.
        if let remoteHead = try? await client.getRef(branch: state.branch).object.sha {
            summary.behind = remoteHead == state.baseCommitSHA ? 0 : 1
        }
        summary.ahead = summary.localChangeCount
        return summary
    }

    // MARK: - Pull

    func pull() async throws {
        guard var state else { throw GitHubError.notConfigured }
        let client = try makeClient(for: state)

        let remoteHead = try await client.getRef(branch: state.branch).object.sha
        if remoteHead == state.baseCommitSHA {
            state.lastSyncDate = Date()
            persist(state)
            status = localChanges(against: state)
            return
        }

        let remoteCommit = try await client.getCommit(sha: remoteHead)
        let remoteTree = try await client.getTree(sha: remoteCommit.tree.sha, recursive: true)
        let remoteEntries = Dictionary(uniqueKeysWithValues:
            remoteTree.tree.filter { $0.type == "blob" }.map { ($0.path, $0) })

        let working = enumerateWorkingFiles()
        var allPaths = Set(state.files.keys)
        allPaths.formUnion(remoteEntries.keys)
        allPaths.formUnion(working.keys)

        var newFiles: [String: String] = [:]
        var skipped = Set(state.skippedPaths)

        for path in allPaths {
            let baseSHA = state.files[path]
            let remote = remoteEntries[path]
            let remoteSHA = remote?.sha
            let localURL = working[path]
            let localData = localURL.flatMap { try? Data(contentsOf: $0) }
            let localSHA = localData.map(GitBlob.sha1(for:))

            let localChanged = localSHA != baseSHA
            let remoteChanged = remoteSHA != baseSHA

            switch (remoteSHA, localSHA) {
            case let (r?, l?):
                if !remoteChanged {
                    // Remote unchanged: keep whatever is local; baseline unchanged.
                    newFiles[path] = baseSHA
                } else if !localChanged {
                    // Only remote changed: take remote.
                    try await takeRemote(path: path, sha: r, client: client, entry: remote, skipped: &skipped, newFiles: &newFiles)
                } else if l == r {
                    // Both arrived at the same content.
                    newFiles[path] = r
                } else if let baseSHA {
                    // Both changed: attempt a three-way line merge.
                    try await mergeFile(path: path, base: baseSHA, remoteSHA: r,
                                        localData: localData!, client: client, newFiles: &newFiles)
                } else {
                    // Both added a different file at the same path: conflict copy.
                    try await conflictCopy(path: path, remoteSHA: r, client: client, newFiles: &newFiles)
                }

            case let (r?, nil):
                // Missing locally.
                if baseSHA == nil {
                    // New remote file.
                    try await takeRemote(path: path, sha: r, client: client, entry: remote, skipped: &skipped, newFiles: &newFiles)
                } else if !remoteChanged {
                    // Locally deleted, remote unchanged: honor the deletion.
                    continue
                } else {
                    // Locally deleted but remote changed: keep the remote version.
                    try await takeRemote(path: path, sha: r, client: client, entry: remote, skipped: &skipped, newFiles: &newFiles)
                }

            case let (nil, l?):
                // Not on remote.
                if baseSHA == nil {
                    // Local-only addition: keep, untracked (pushed on next commit).
                    continue
                } else if l == baseSHA {
                    // Remote deleted, local unchanged: delete locally.
                    if let localURL { try? fileManager.removeItem(at: localURL) }
                    continue
                } else {
                    // Remote deleted, local modified: keep local, treat as new add.
                    continue
                }

            case (nil, nil):
                // Gone from both: drop from baseline.
                continue
            }
        }

        state.files = newFiles
        state.skippedPaths = Array(skipped).filter { newFiles[$0] != nil }
        state.baseCommitSHA = remoteHead
        state.lastSyncDate = Date()
        persist(state)
        repo.refresh()
        status = localChanges(against: state)
    }

    private func takeRemote(path: String, sha: String, client: GitHubClient,
                            entry: GitHubClient.TreeEntry?, skipped: inout Set<String>,
                            newFiles: inout [String: String]) async throws {
        newFiles[path] = sha
        if let size = entry?.size, size > maxBlobDownloadBytes {
            skipped.insert(path)
            return
        }
        skipped.remove(path)
        let data = try await client.getBlobData(sha: sha)
        try writeWorkingFile(path: path, data: data)
    }

    private func mergeFile(path: String, base: String, remoteSHA: String,
                           localData: Data, client: GitHubClient,
                           newFiles: inout [String: String]) async throws {
        let baseData = try await client.getBlobData(sha: base)
        let remoteData = try await client.getBlobData(sha: remoteSHA)

        guard let baseText = String(data: baseData, encoding: .utf8),
              let localText = String(data: localData, encoding: .utf8),
              let remoteText = String(data: remoteData, encoding: .utf8) else {
            // Binary or non-UTF8: cannot merge, keep a conflict copy of remote.
            try await conflictCopy(path: path, remoteSHA: remoteSHA, client: client, newFiles: &newFiles)
            return
        }

        let merged = ThreeWayMerge.merge(base: baseText, local: localText, remote: remoteText)
        if merged.hasConflict {
            // Keep local; drop the remote copy alongside it.
            try writeConflictSidecar(path: path, data: remoteData, remoteSHA: remoteSHA)
            newFiles[path] = remoteSHA
        } else {
            try writeWorkingFile(path: path, data: Data(merged.text.utf8))
            newFiles[path] = remoteSHA
        }
    }

    private func conflictCopy(path: String, remoteSHA: String, client: GitHubClient,
                              newFiles: inout [String: String]) async throws {
        let remoteData = try await client.getBlobData(sha: remoteSHA)
        try writeConflictSidecar(path: path, data: remoteData, remoteSHA: remoteSHA)
        newFiles[path] = remoteSHA
    }

    // MARK: - Push

    func commitAndPush(message: String? = nil) async throws {
        try await commitAndPush(message: message, allowRetry: true)
    }

    private func commitAndPush(message: String?, allowRetry: Bool) async throws {
        guard let state else { throw GitHubError.notConfigured }
        let client = try makeClient(for: state)

        // A conflict sidecar is intentionally left beside the local file for
        // review. Do not turn the next ordinary Sync into an implicit
        // local-wins force overwrite; require the user to resolve/remove it.
        if enumerateWorkingFiles().keys.contains(where: { $0.contains(" (conflict ") }) {
            throw GitHubError.server(status: 409, message: "Resolve conflict copies before committing and pushing")
        }

        let changes = localChanges(against: state)
        guard changes.hasLocalChanges else {
            status = changes
            return
        }

        let working = enumerateWorkingFiles()
        var entries: [TreeEntryInput] = []

        for path in changes.modified + changes.added {
            guard let url = working[path], let data = try? Data(contentsOf: url) else { continue }
            phase = .syncing("Uploading \(path)…")
            let blobSHA = try await client.createBlob(data: data)
            entries.append(TreeEntryInput(path: path, sha: blobSHA))
        }
        for path in changes.deleted {
            entries.append(TreeEntryInput(path: path, sha: nil))
        }

        let baseCommit = try await client.getCommit(sha: state.baseCommitSHA)
        let newTree = try await client.createTree(baseTree: baseCommit.tree.sha, entries: entries)
        let commitMessage = message ?? defaultMessage(for: changes)
        let newCommit = try await client.createCommit(message: commitMessage, tree: newTree,
                                                      parents: [state.baseCommitSHA])

        do {
            try await client.updateRef(branch: state.branch, sha: newCommit, force: false)
        } catch GitHubError.nonFastForward where allowRetry {
            // Remote moved: pull to reconcile, then retry the push once.
            try await pull()
            try await commitAndPush(message: message, allowRetry: false)
            return
        }

        // Success: realign the baseline to the new commit.
        rebaseState(to: newCommit)
    }

    private func defaultMessage(for changes: SyncStatus) -> String {
        let n = changes.localChangeCount
        return "OrgSync: update \(n) file\(n == 1 ? "" : "s")"
    }

    // MARK: - Sync

    func sync() async throws {
        try await pull()
        let changes = localChanges(against: state ?? nil)
        if changes.hasLocalChanges {
            try await commitAndPush(message: nil)
        }
    }

    // MARK: - Commit log

    func recentCommits(limit: Int = 30) async throws -> [CommitSummary] {
        let client: GitHubClient
        let branch: String
        if let state {
            client = try makeClient(for: state)
            branch = state.branch
        } else {
            client = try makeClientFromSettings()
            branch = settings.branch.isEmpty ? "main" : settings.branch
        }
        return try await client.listCommits(branch: branch, limit: limit).map {
            CommitSummary(sha: $0.sha, message: $0.commit.message,
                          authorName: $0.commit.author.name, date: $0.commit.author.date)
        }
    }

    // MARK: - Local change detection

    private func localChanges(against state: SyncRepoState?) -> SyncStatus {
        guard let state else { return SyncStatus() }
        var result = SyncStatus()
        let working = enumerateWorkingFiles()

        for (path, url) in working {
            if state.skippedPaths.contains(path) { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let sha = GitBlob.sha1(for: data)
            if let base = state.files[path] {
                if base != sha { result.modified.append(path) }
            } else {
                result.added.append(path)
            }
        }
        for path in state.files.keys where working[path] == nil && !state.skippedPaths.contains(path) {
            result.deleted.append(path)
        }
        result.modified.sort(); result.added.sort(); result.deleted.sort()
        return result
    }

    /// Recomputes the baseline from the current working files after a successful
    /// push, so the just-pushed content becomes the new merge base.
    private func rebaseState(to commit: String) {
        guard var state else { return }
        let working = enumerateWorkingFiles()
        var files: [String: String] = [:]
        // Preserve skipped (undownloaded) blobs; they are unchanged by a push.
        for path in state.skippedPaths { files[path] = state.files[path] }
        for (path, url) in working {
            if state.skippedPaths.contains(path) { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            files[path] = GitBlob.sha1(for: data)
        }
        state.files = files
        state.baseCommitSHA = commit
        state.lastSyncDate = Date()
        persist(state)
    }

    // MARK: - Working-copy IO

    /// Repo-relative path -> file URL for every regular file in the working copy,
    /// excluding the `.orgsync` metadata and the pre-sync backup folder.
    private func enumerateWorkingFiles() -> [String: URL] {
        let root = repo.repoURL
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var files: [String: URL] = [:]
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let path = relativePath(for: url, root: root)
            if path.hasPrefix(".orgsync/") || path.hasPrefix("pre-sync-backup/") { continue }
            files[path] = url
        }
        return files
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count,
              Array(urlComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.lastPathComponent
        }
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func writeWorkingFile(path: String, data: Data) throws {
        let url = repo.repoURL.appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func writeConflictSidecar(path: String, data: Data, remoteSHA: String) throws {
        let url = repo.repoURL.appendingPathComponent(path)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let sidecarName = ext.isEmpty
            ? "\(base) (conflict \(remoteSHA.prefix(7)))"
            : "\(base) (conflict \(remoteSHA.prefix(7))).\(ext)"
        let sidecarURL = url.deletingLastPathComponent().appendingPathComponent(sidecarName)
        try fileManager.createDirectory(at: sidecarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: sidecarURL, options: .atomic)
    }

    private func clearWorkingCopy() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: repo.repoURL, includingPropertiesForKeys: nil, options: []) else { return }
        for url in contents {
            let name = url.lastPathComponent
            if name == ".orgsync" || name == "pre-sync-backup" { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    /// Copies the current working copy into `Documents/pre-sync-backup`, but only
    /// the first time (so a later re-clone doesn't clobber an earlier backup).
    private func backupWorkingCopyOnce() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backup = documents.appendingPathComponent("pre-sync-backup", isDirectory: true)
        guard !fileManager.fileExists(atPath: backup.path) else { return }
        try? fileManager.copyItem(at: repo.repoURL, to: backup)
    }

    // MARK: - Client construction

    private func makeClientFromSettings() throws -> GitHubClient {
        let token = currentToken()
        guard !token.isEmpty else { throw GitHubError.notConfigured }
        let (owner, repoName) = try GitHubClient.parseRepository(settings.repoURL)
        return GitHubClient(token: token, owner: owner, repo: repoName)
    }

    private func makeClient(for state: SyncRepoState) throws -> GitHubClient {
        let token = currentToken()
        guard !token.isEmpty else { throw GitHubError.notConfigured }
        return GitHubClient(token: token, owner: state.owner, repo: state.repo)
    }

    private func currentToken() -> String {
        KeychainHelper.get(account: SettingsStore.tokenAccount) ?? settings.token
    }

    // MARK: - State persistence

    private func persist(_ newState: SyncRepoState) {
        state = newState
        let url = Self.stateURL(repoRoot: repo.repoURL)
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(newState) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func stateURL(repoRoot: URL) -> URL {
        repoRoot.appendingPathComponent(".orgsync/state.json")
    }

    private static func loadState(from url: URL) -> SyncRepoState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SyncRepoState.self, from: data)
    }
}
