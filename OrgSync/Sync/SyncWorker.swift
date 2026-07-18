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

    func pull(state initialState: SyncRepoState, client: GitHubClient) async throws -> Result {
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
        let pulled = try await pull(state: state, client: client)
        guard pulled.status.hasLocalChanges else { return pulled }
        return try await commitAndPush(state: pulled.state, client: client, message: nil, allowRetry: true)
    }

    func commitAndPush(state: SyncRepoState, client: GitHubClient, message: String?, allowRetry: Bool = true) async throws -> Result {
        if enumerateWorkingFiles().keys.contains(where: { $0.contains(" (conflict ") }) {
            throw GitHubError.server(status: 409, message: "Resolve conflict copies before committing and pushing")
        }
        let changes = localChanges(against: state)
        guard changes.hasLocalChanges else { return Result(state: state, status: changes) }
        let working = enumerateWorkingFiles()
        var entries: [TreeEntryInput] = []
        for path in changes.modified + changes.added {
            guard let url = working[path], let data = try? Data(contentsOf: url) else { continue }
            entries.append(TreeEntryInput(path: path, sha: try await client.createBlob(data: data)))
        }
        for path in changes.deleted { entries.append(TreeEntryInput(path: path, sha: nil)) }

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
        var rebased = state
        rebase(&rebased, to: commit)
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

    private func rebase(_ state: inout SyncRepoState, to commit: String) {
        let working = enumerateWorkingFiles()
        var files: [String: String] = [:]
        for path in state.skippedPaths { files[path] = state.files[path] }
        for (path, url) in working where !state.skippedPaths.contains(path) {
            if let data = try? Data(contentsOf: url) { files[path] = GitBlob.sha1(for: data) }
        }
        state.files = files
        state.baseCommitSHA = commit
        state.lastSyncDate = Date()
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
