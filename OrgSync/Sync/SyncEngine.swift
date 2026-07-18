//
//  SyncEngine.swift
//  OrgSync
//
//  Main-actor observable facade for SwiftUI. SyncWorker owns filesystem,
//  hashing, merge, persistence, and network orchestration off the main actor.
//

import Foundation
import Observation

@MainActor
@Observable
final class SyncEngine {
    struct ConflictCopy: Identifiable, Hashable {
        var sidecarURL: URL
        var originalURL: URL
        var id: URL { sidecarURL }
        var fileName: String { originalURL.lastPathComponent }
    }

    enum Phase: Equatable {
        case idle
        case syncing(String)
        case error(String)

        var isBusy: Bool { if case .syncing = self { true } else { false } }
    }

    private(set) var phase: Phase = .idle
    private(set) var status = SyncStatus()
    private(set) var lastSyncDate: Date?
    var lastError: String?

    var isConnected: Bool { state != nil }
    var connectedRepoName: String? { state.map { "\($0.owner)/\($0.repo)" } }
    var connectedBranch: String? { state?.branch }
    var stagedChangeCount: Int { state?.stagedPaths.count ?? 0 }
    var hasPendingCommit: Bool { state?.pendingCommit != nil }
    var pendingCommitSHA: String? { state?.pendingCommit.map { String($0.sha.prefix(7)) } }

    private let repo: RepoStore
    private let settings: SettingsStore
    private let worker: SyncWorker
    private let fileManager = FileManager.default
    private var state: SyncRepoState? {
        didSet { lastSyncDate = state?.lastSyncDate }
    }

    init(repo: RepoStore, settings: SettingsStore) {
        self.repo = repo
        self.settings = settings
        self.worker = SyncWorker(repoURL: repo.repoURL)
        self.state = Self.loadState(from: Self.stateURL(repoRoot: repo.repoURL))
        self.lastSyncDate = state?.lastSyncDate
    }

    // MARK: - User-driven wrappers

    func syncNow() async { await run("Syncing…") { try await self.sync() } }
    func pullNow() async { await run("Pulling…") { try await self.pull() } }
    func pushNow(message: String? = nil) async { await run("Pushing…") { try await self.commitAndPush(message: message) } }
    func stageAllNow() async {
        await run("Staging…") {
            guard let state = self.state else { throw GitHubError.notConfigured }
            self.apply(await self.worker.stageAll(state: state))
        }
    }
    func commitStagedNow(message: String? = nil) async {
        await run("Committing…") {
            guard let state = self.state else { throw GitHubError.notConfigured }
            self.apply(try await self.worker.commitStaged(state: state, client: try self.makeClient(for: state), message: message))
        }
    }
    func pushPendingNow() async {
        await run("Pushing…") {
            guard let state = self.state else { throw GitHubError.notConfigured }
            self.apply(try await self.worker.pushPending(state: state, client: try self.makeClient(for: state)))
        }
    }

    func discardPendingCommitNow() async {
        await run("Discarding…") {
            guard let state = self.state else { throw GitHubError.notConfigured }
            self.apply(await self.worker.discardPendingCommit(state: state))
        }
    }

    private func run(_ label: String, _ operation: @escaping () async throws -> Void) async {
        phase = .syncing(label)
        do {
            try await operation()
            phase = .idle
        } catch {
            let text = message(for: error)
            phase = .error(text)
            lastError = text
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Validation / connection

    func validateRepository() async throws -> GitHubClient.RepoInfo {
        try await makeClientFromSettings().getRepo()
    }

    func availableBranches() async throws -> [String] {
        try await makeClientFromSettings().listBranches().map(\.name)
    }

    func connect(branch: String) async throws {
        phase = .syncing("Connecting…")
        do {
            let client = try makeClientFromSettings()
            let info = try await client.getRepo()
            phase = .syncing("Fetching \(info.name)…")
            apply(try await worker.connect(branch: branch, owner: client.owner, repo: client.repo, client: client))
            repo.refresh()
            phase = .idle
            AppReviewPrompter.requestAfterRepositoryConnection()
        } catch {
            phase = .idle
            throw error
        }
    }

    func disconnect(deleteLocalFiles: Bool) async {
        if deleteLocalFiles {
            await worker.removeWorkingCopy()
            repo.refresh()
        }
        await worker.removePersistedState()
        state = nil
        status = SyncStatus()
        phase = .idle
    }

    // MARK: - Conflict resolution

    func conflictCopies() -> [ConflictCopy] {
        let root = repo.repoURL
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.compactMap { sidecar in
            let ext = sidecar.pathExtension
            let stem = sidecar.deletingPathExtension().lastPathComponent
            guard let range = stem.range(of: " (conflict ", options: .backwards) else { return nil }
            let originalStem = String(stem[..<range.lowerBound])
            let originalName = ext.isEmpty ? originalStem : originalStem + "." + ext
            return ConflictCopy(sidecarURL: sidecar, originalURL: sidecar.deletingLastPathComponent().appendingPathComponent(originalName))
        }.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    func resolveConflictKeepingLocal(_ conflict: ConflictCopy) {
        try? fileManager.removeItem(at: conflict.sidecarURL)
        repo.refresh()
    }

    func resolveConflictUsingRemote(_ conflict: ConflictCopy) {
        guard fileManager.fileExists(atPath: conflict.sidecarURL.path) else { return }
        try? fileManager.removeItem(at: conflict.originalURL)
        try? fileManager.moveItem(at: conflict.sidecarURL, to: conflict.originalURL)
        repo.refresh()
    }

    // MARK: - Sync operations

    @discardableResult
    func refreshStatus() async throws -> SyncStatus {
        guard let state else { throw GitHubError.notConfigured }
        let result = try await worker.refreshStatus(state: state, client: try makeClient(for: state))
        status = result
        return result
    }

    func pull() async throws {
        guard let state else { throw GitHubError.notConfigured }
        apply(try await worker.pull(state: state, client: try makeClient(for: state)))
        repo.refresh()
    }

    func commitAndPush(message: String? = nil) async throws {
        guard let state else { throw GitHubError.notConfigured }
        apply(try await worker.commitAndPush(state: state, client: try makeClient(for: state), message: message))
    }

    func sync() async throws {
        guard let state else { throw GitHubError.notConfigured }
        apply(try await worker.sync(state: state, client: try makeClient(for: state)))
        repo.refresh()
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
            CommitSummary(sha: $0.sha, message: $0.commit.message, authorName: $0.commit.author.name, date: $0.commit.author.date)
        }
    }

    private func apply(_ result: SyncWorker.Result) {
        state = result.state
        status = result.status
    }

    // MARK: - Client construction

    private func makeClientFromSettings() throws -> GitHubClient {
        let token = currentToken()
        guard !token.isEmpty else { throw GitHubError.notConfigured }
        let parsed = try GitHubClient.parseRepository(settings.repoURL)
        return GitHubClient(token: token, owner: parsed.owner, repo: parsed.repo)
    }

    private func makeClient(for state: SyncRepoState) throws -> GitHubClient {
        let token = currentToken()
        guard !token.isEmpty else { throw GitHubError.notConfigured }
        return GitHubClient(token: token, owner: state.owner, repo: state.repo)
    }

    private func currentToken() -> String {
        KeychainHelper.get(account: SettingsStore.tokenAccount) ?? settings.token
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
