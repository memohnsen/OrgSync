//
//  SyncWorker.swift
//  OrgSync
//
//  Serializes slow sync work away from the main actor. The observable
//  SyncEngine applies the resulting state on the main actor for SwiftUI.
//

import Foundation

actor SyncWorker {
    struct Result: Sendable {
        let state: SyncRepoState
        let status: SyncStatus
    }

    private let repoURL: URL
    private let maxBlobDownloadBytes: Int
    private let fileManager = FileManager.default

    init(repoURL: URL, maxBlobDownloadBytes: Int = 5 * 1024 * 1024) {
        self.repoURL = repoURL
        self.maxBlobDownloadBytes = maxBlobDownloadBytes
    }

    func connect(branch: String, owner: String, repo: String, client: GitHubClient) async throws -> Result {
        let head = try await client.getRef(branch: branch).object.sha
        let commit = try await client.getCommit(sha: head)
        let tree = try await client.getTree(sha: commit.tree.sha, recursive: true)
        guard !tree.truncated else {
            throw GitHubError.decoding("repository tree is too large for a safe initial clone")
        }
        let blobs = tree.tree.filter { $0.type == "blob" }

        if !blobs.isEmpty && !enumerateWorkingFiles().isEmpty {
            backupWorkingCopyOnce()
            clearWorkingCopy()
        }

        var files: [String: String] = [:]
        var skipped: [String] = []
        for entry in blobs {
            files[entry.path] = entry.sha
            if let size = entry.size, size > maxBlobDownloadBytes {
                skipped.append(entry.path)
                continue
            }
            try writeWorkingFile(path: entry.path, data: try await client.getBlobData(sha: entry.sha))
        }

        var state = SyncRepoState(owner: owner, repo: repo, branch: branch,
                                  baseCommitSHA: head, files: files, skippedPaths: skipped)
        state.lastSyncDate = Date()
        persist(state)
        return Result(state: state, status: try await computeStatus(using: client, state: state))
    }

    func refreshStatus(state: SyncRepoState, client: GitHubClient) async throws -> SyncStatus {
        try await computeStatus(using: client, state: state)
    }

    /// Local-only status calculation, exposed internally for deterministic
    /// coverage of working-copy change classification.
    func localStatus(state: SyncRepoState) -> SyncStatus {
        localChanges(against: state)
    }

    /// Marks every local change for the next commit. OrgSync has no separate
    /// on-device git index; this persisted list is its lightweight equivalent.
    func stageAll(state initialState: SyncRepoState) -> Result {
        var state = initialState
        let status = localChanges(against: state)
        state.stagedPaths = status.changedPaths
        persist(state)
        return Result(state: state, status: status)
    }

    /// Creates a Git commit object without moving the remote branch ref.
    func commitStaged(state initialState: SyncRepoState, client: GitHubClient, message: String?) async throws -> Result {
        guard initialState.pendingCommit == nil else {
            throw GitHubError.server(status: 409, message: "Push the pending commit before creating another commit")
        }
        let current = localChanges(against: initialState)
        let staged = Set(initialState.stagedPaths)
        let modified = current.modified.filter { staged.contains($0) }
        let added = current.added.filter { staged.contains($0) }
        let deleted = current.deleted.filter { staged.contains($0) }
        guard !modified.isEmpty || !added.isEmpty || !deleted.isEmpty else {
            throw GitHubError.server(status: 422, message: "Stage one or more changes before committing")
        }

        let working = enumerateWorkingFiles()
        var entries: [TreeEntryInput] = []
        var pendingChanges: [PendingGitCommit.Change] = []
        for path in modified + added {
            guard let url = working[path], let data = try? Data(contentsOf: url) else { continue }
            let blobSHA = try await client.createBlob(data: data)
            entries.append(TreeEntryInput(path: path, sha: blobSHA))
            pendingChanges.append(.init(path: path, blobSHA: blobSHA))
        }
        for path in deleted {
            entries.append(TreeEntryInput(path: path, sha: nil))
            pendingChanges.append(.init(path: path, blobSHA: nil))
        }

        let baseCommit = try await client.getCommit(sha: initialState.baseCommitSHA)
        let tree = try await client.createTree(baseTree: baseCommit.tree.sha, entries: entries)
        let count = pendingChanges.count
        let commitSHA = try await client.createCommit(
            message: message ?? "OrgSync: update \(count) file\(count == 1 ? "" : "s")",
            tree: tree,
            parents: [initialState.baseCommitSHA]
        )
        var state = initialState
        state.stagedPaths = []
        state.pendingCommit = PendingGitCommit(sha: commitSHA, changes: pendingChanges)
        persist(state)
        return Result(state: state, status: localChanges(against: state))
    }

    /// Publishes a previously created commit by advancing the branch ref.
    func pushPending(state initialState: SyncRepoState, client: GitHubClient) async throws -> Result {
        guard let pending = initialState.pendingCommit else {
            throw GitHubError.server(status: 422, message: "Create a commit before pushing")
        }
        try await client.updateRef(branch: initialState.branch, sha: pending.sha, force: false)
        var state = initialState
        for change in pending.changes {
            if let blobSHA = change.blobSHA { state.files[change.path] = blobSHA }
            else { state.files.removeValue(forKey: change.path) }
        }
        state.baseCommitSHA = pending.sha
        state.pendingCommit = nil
        state.lastSyncDate = Date()
        persist(state)
        return Result(state: state, status: localChanges(against: state))
    }

    /// Abandons a locally created commit object without publishing it. The
    /// working copy is untouched, so its changes become plain local changes
    /// again. This is the escape hatch when the remote moved and the pending
    /// commit can no longer fast-forward.
    func discardPendingCommit(state initialState: SyncRepoState) -> Result {
        var state = initialState
        state.pendingCommit = nil
        persist(state)
        return Result(state: state, status: localChanges(against: state))
    }

    func pull(state initialState: SyncRepoState, client: GitHubClient) async throws -> Result {
        guard initialState.pendingCommit == nil else {
            throw GitHubError.server(status: 409, message: "Push the pending commit before pulling remote changes")
        }
        var state = initialState
        let remoteHead = try await client.getRef(branch: state.branch).object.sha
        if remoteHead == state.baseCommitSHA {
            state.lastSyncDate = Date()
            persist(state)
            return Result(state: state, status: localChanges(against: state))
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
            case let (remoteSHA?, localSHA?):
                if !remoteChanged { newFiles[path] = baseSHA }
                else if !localChanged {
                    try await takeRemote(path: path, sha: remoteSHA, client: client, entry: remote, skipped: &skipped, newFiles: &newFiles)
                } else if localSHA == remoteSHA { newFiles[path] = remoteSHA }
                else if let baseSHA {
                    try await mergeFile(path: path, base: baseSHA, remoteSHA: remoteSHA, localData: localData!, client: client, newFiles: &newFiles)
                } else {
                    try await conflictCopy(path: path, remoteSHA: remoteSHA, client: client, newFiles: &newFiles)
                }
            case let (remoteSHA?, nil):
                if baseSHA == nil || remoteChanged {
                    try await takeRemote(path: path, sha: remoteSHA, client: client, entry: remote, skipped: &skipped, newFiles: &newFiles)
                } else {
                    // Locally deleted (or skipped and never downloaded) with an
                    // unchanged remote: keep the baseline entry so the deletion
                    // stays a visible local change to push, and the skipped
                    // path isn't forgotten and re-downloaded next pull.
                    newFiles[path] = baseSHA
                }
            case let (nil, localSHA?):
                if baseSHA != nil && localSHA == baseSHA, let localURL { try? fileManager.removeItem(at: localURL) }
            case (nil, nil):
                break
            }
        }

        state.files = newFiles
        state.skippedPaths = Array(skipped).filter { newFiles[$0] != nil }
        state.baseCommitSHA = remoteHead
        state.lastSyncDate = Date()
        persist(state)
        return Result(state: state, status: localChanges(against: state))
    }

    func sync(state: SyncRepoState, client: GitHubClient) async throws -> Result {
        if state.pendingCommit != nil { return try await pushPending(state: state, client: client) }
        let pulled = try await pull(state: state, client: client)
        guard pulled.status.hasLocalChanges else { return pulled }
        return try await commitAndPush(state: pulled.state, client: client, message: nil, allowRetry: true)
    }

    func commitAndPush(state: SyncRepoState, client: GitHubClient, message: String?, allowRetry: Bool = true) async throws -> Result {
        if state.pendingCommit != nil { return try await pushPending(state: state, client: client) }
        if enumerateWorkingFiles().keys.contains(where: { $0.contains(" (conflict ") }) {
            throw GitHubError.server(status: 409, message: "Resolve conflict copies before committing and pushing")
        }
        let changes = localChanges(against: state)
        guard changes.hasLocalChanges else { return Result(state: state, status: changes) }
        let working = enumerateWorkingFiles()
        var entries: [TreeEntryInput] = []
        var applied: [PendingGitCommit.Change] = []
        for path in changes.modified + changes.added {
            guard let url = working[path], let data = try? Data(contentsOf: url) else { continue }
            let blobSHA = try await client.createBlob(data: data)
            entries.append(TreeEntryInput(path: path, sha: blobSHA))
            applied.append(.init(path: path, blobSHA: blobSHA))
        }
        for path in changes.deleted {
            entries.append(TreeEntryInput(path: path, sha: nil))
            applied.append(.init(path: path, blobSHA: nil))
        }

        let baseCommit = try await client.getCommit(sha: state.baseCommitSHA)
        let tree = try await client.createTree(baseTree: baseCommit.tree.sha, entries: entries)
        let count = changes.localChangeCount
        let commit = try await client.createCommit(
            message: message ?? "OrgSync: update \(count) file\(count == 1 ? "" : "s")",
            tree: tree, parents: [state.baseCommitSHA]
        )
        do {
            try await client.updateRef(branch: state.branch, sha: commit, force: false)
        } catch GitHubError.nonFastForward where allowRetry {
            let pulled = try await pull(state: state, client: client)
            return try await commitAndPush(state: pulled.state, client: client, message: message, allowRetry: false)
        }
        // The new baseline reflects exactly the blobs that were uploaded — never
        // a fresh disk scan, which would absorb files edited or created while
        // the push was in flight and later clobber or delete them on pull.
        var rebased = state
        for change in applied {
            if let blobSHA = change.blobSHA { rebased.files[change.path] = blobSHA }
            else { rebased.files.removeValue(forKey: change.path) }
        }
        rebased.baseCommitSHA = commit
        rebased.lastSyncDate = Date()
        rebased.stagedPaths = []
        persist(rebased)
        return Result(state: rebased, status: localChanges(against: rebased))
    }

    func removeWorkingCopy() { clearWorkingCopy() }

    func removePersistedState() {
        try? fileManager.removeItem(at: repoURL.appendingPathComponent(".orgsync/state.json"))
    }

    private func computeStatus(using client: GitHubClient, state: SyncRepoState) async throws -> SyncStatus {
        var summary = localChanges(against: state)
        if let remoteHead = try? await client.getRef(branch: state.branch).object.sha {
            summary.behind = remoteHead == state.baseCommitSHA ? 0 : 1
        }
        return summary
    }

    private func takeRemote(path: String, sha: String, client: GitHubClient, entry: GitHubClient.TreeEntry?, skipped: inout Set<String>, newFiles: inout [String: String]) async throws {
        newFiles[path] = sha
        if let size = entry?.size, size > maxBlobDownloadBytes { skipped.insert(path); return }
        skipped.remove(path)
        try writeWorkingFile(path: path, data: try await client.getBlobData(sha: sha))
    }

    private func mergeFile(path: String, base: String, remoteSHA: String, localData: Data, client: GitHubClient, newFiles: inout [String: String]) async throws {
        let baseData = try await client.getBlobData(sha: base)
        let remoteData = try await client.getBlobData(sha: remoteSHA)
        guard let baseText = String(data: baseData, encoding: .utf8),
              let localText = String(data: localData, encoding: .utf8),
              let remoteText = String(data: remoteData, encoding: .utf8) else {
            try writeConflictSidecar(path: path, data: remoteData, remoteSHA: remoteSHA)
            newFiles[path] = remoteSHA
            return
        }
        let merged = ThreeWayMerge.merge(base: baseText, local: localText, remote: remoteText)
        if merged.hasConflict { try writeConflictSidecar(path: path, data: remoteData, remoteSHA: remoteSHA) }
        else { try writeWorkingFile(path: path, data: Data(merged.text.utf8)) }
        newFiles[path] = remoteSHA
    }

    private func conflictCopy(path: String, remoteSHA: String, client: GitHubClient, newFiles: inout [String: String]) async throws {
        try writeConflictSidecar(path: path, data: try await client.getBlobData(sha: remoteSHA), remoteSHA: remoteSHA)
        newFiles[path] = remoteSHA
    }

    private func localChanges(against state: SyncRepoState) -> SyncStatus {
        var result = SyncStatus()
        let working = enumerateWorkingFiles()
        for (path, url) in working {
            if state.skippedPaths.contains(path) { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let sha = GitBlob.sha1(for: data)
            if let base = state.files[path] { if base != sha { result.modified.append(path) } }
            else { result.added.append(path) }
        }
        for path in state.files.keys where working[path] == nil && !state.skippedPaths.contains(path) { result.deleted.append(path) }
        result.modified.sort(); result.added.sort(); result.deleted.sort()
        return result
    }

    private func enumerateWorkingFiles() -> [String: URL] {
        guard let enumerator = fileManager.enumerator(at: repoURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [:] }
        var files: [String: URL] = [:]
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = relativePath(for: url)
            if !path.hasPrefix(".orgsync/") && !path.hasPrefix("pre-sync-backup/") { files[path] = url }
        }
        return files
    }

    private func relativePath(for url: URL) -> String {
        let root = repoURL.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count > root.count, Array(components.prefix(root.count)) == root else { return url.lastPathComponent }
        return components.dropFirst(root.count).joined(separator: "/")
    }

    private func writeWorkingFile(path: String, data: Data) throws {
        let url = repoURL.appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func writeConflictSidecar(path: String, data: Data, remoteSHA: String) throws {
        let url = repoURL.appendingPathComponent(path)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let name = ext.isEmpty ? "\(base) (conflict \(remoteSHA.prefix(7)))" : "\(base) (conflict \(remoteSHA.prefix(7))).\(ext)"
        let sidecar = url.deletingLastPathComponent().appendingPathComponent(name)
        try fileManager.createDirectory(at: sidecar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: sidecar, options: .atomic)
    }

    private func clearWorkingCopy() {
        guard let contents = try? fileManager.contentsOfDirectory(at: repoURL, includingPropertiesForKeys: nil, options: []) else { return }
        for url in contents where url.lastPathComponent != ".orgsync" && url.lastPathComponent != "pre-sync-backup" { try? fileManager.removeItem(at: url) }
    }

    private func backupWorkingCopyOnce() {
        let backup = repoURL.deletingLastPathComponent().appendingPathComponent("pre-sync-backup", isDirectory: true)
        guard !fileManager.fileExists(atPath: backup.path) else { return }
        try? fileManager.copyItem(at: repoURL, to: backup)
    }

    private func persist(_ state: SyncRepoState) {
        let url = repoURL.appendingPathComponent(".orgsync/state.json")
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) { try? data.write(to: url, options: .atomic) }
    }
}
