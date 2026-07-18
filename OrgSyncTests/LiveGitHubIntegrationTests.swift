//
//  LiveGitHubIntegrationTests.swift
//  OrgSyncTests
//
//  An opt-in check against the disposable App Review repository. It confirms
//  that a real fine-grained PAT can authenticate, inspect the repository, and
//  drive OrgSync's actual clone and pull flow. It deliberately never writes to
//  main; push/conflict behavior is covered deterministically by FakeGitHub.
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct LiveGitHubIntegrationTests {
    @Test func reviewerRepositoryAuthenticatesClonesAndPulls() async throws {
        guard ReviewerGitCredentials.isEnabled else { return }
        let credentials = try ReviewerGitCredentials.load()
        let parsed = try GitHubClient.parseRepository(credentials.repositoryURL)
        let client = GitHubClient(token: credentials.token, owner: parsed.owner, repo: parsed.repo)

        let info = try await client.getRepo()
        #expect(info.fullName == "\(parsed.owner)/\(parsed.repo)")
        let branches = try await client.listBranches()
        #expect(branches.contains(where: { $0.name == credentials.branch }))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let worker = SyncWorker(repoURL: root)
        let connected = try await worker.connect(branch: credentials.branch, owner: parsed.owner, repo: parsed.repo, client: client)
        #expect(connected.state.baseCommitSHA.isEmpty == false)
        #expect(connected.status.hasLocalChanges == false)

        let pulled = try await worker.pull(state: connected.state, client: client)
        #expect(pulled.state.baseCommitSHA == connected.state.baseCommitSHA)
        #expect(pulled.status.hasLocalChanges == false)
    }
}

private struct ReviewerGitCredentials {
    let repositoryURL: String
    let token: String
    let branch: String

    private static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent(".orgsync-live-git-enabled").path)
    }

    static func load() throws -> ReviewerGitCredentials {
        let environment = ProcessInfo.processInfo.environment.merging(loadDotEnv(), uniquingKeysWith: { current, _ in current })
        guard let repositoryURL = environment["ORGSYNC_REVIEW_REPO_URL"], !repositoryURL.isEmpty,
              let token = environment["ORGSYNC_REVIEW_PAT"], !token.isEmpty else {
            throw NSError(domain: "OrgSyncTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Set ORGSYNC_REVIEW_REPO_URL and ORGSYNC_REVIEW_PAT in the ignored .env file before running the live Git test."
            ])
        }
        return ReviewerGitCredentials(
            repositoryURL: repositoryURL,
            token: token,
            branch: environment["ORGSYNC_REVIEW_BRANCH"] ?? "main"
        )
    }

    private static func loadDotEnv() -> [String: String] {
        let file = projectRoot.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        return Dictionary(uniqueKeysWithValues: text.split(whereSeparator: \.isNewline).compactMap { line in
            let pieces = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2, !pieces[0].hasPrefix("#") else { return nil }
            return (String(pieces[0]), String(pieces[1]))
        })
    }
}
