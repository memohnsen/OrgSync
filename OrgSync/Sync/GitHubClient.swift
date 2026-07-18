//
//  GitHubClient.swift
//  OrgSync
//
//  A thin async/await wrapper over the GitHub REST v3 API (the Git Data API for
//  blobs/trees/commits/refs, plus repo metadata and the commit list). Auth is a
//  fine-grained Personal Access Token supplied by the caller (read from the
//  Keychain by the sync engine); the token is only ever placed in the
//  Authorization header, never logged.
//
//  Errors are mapped to a small, actionable surface so the UI can distinguish
//  auth failure, missing repo, rate limiting, a non-fast-forward push, and
//  transport problems.
//

import Foundation

// MARK: - Errors

enum GitHubError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case invalidRepositoryURL(String)
    case authenticationFailed
    case notFound
    case rateLimited(resetDate: Date?)
    case nonFastForward
    case network(String)
    case server(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add a repository URL and Personal Access Token in Settings first."
        case .invalidRepositoryURL(let value):
            return "Couldn't read a GitHub owner/repository from \"\(value)\"."
        case .authenticationFailed:
            return "GitHub rejected the Personal Access Token. Check that it has read/write access to the repository."
        case .notFound:
            return "The repository or branch could not be found."
        case .rateLimited(let reset):
            if let reset {
                let f = RelativeDateTimeFormatter()
                return "GitHub rate limit reached. Try again \(f.localizedString(for: reset, relativeTo: Date()))."
            }
            return "GitHub rate limit reached. Try again shortly."
        case .nonFastForward:
            return "The branch moved on GitHub. Pull the latest changes and try again."
        case .network(let message):
            return "Network error: \(message)"
        case .server(let status, let message):
            return "GitHub error (\(status)): \(message)"
        case .decoding(let message):
            return "Unexpected response from GitHub: \(message)"
        }
    }
}

// MARK: - Response models

extension GitHubClient {
    struct RepoInfo: Decodable, Sendable {
        let name: String
        let fullName: String
        let description: String?
        let defaultBranch: String
        let isPrivate: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case fullName = "full_name"
            case description
            case defaultBranch = "default_branch"
            case isPrivate = "private"
        }
    }

    struct BranchRef: Decodable, Sendable { let name: String }

    struct GitObject: Decodable, Sendable { let sha: String; let type: String? }
    struct Ref: Decodable, Sendable { let ref: String; let object: GitObject }

    struct TreePointer: Decodable, Sendable { let sha: String }
    struct Commit: Decodable, Sendable {
        let sha: String
        let tree: TreePointer
        let message: String
    }

    struct TreeEntry: Decodable, Sendable {
        let path: String
        let mode: String
        let type: String
        let sha: String
        let size: Int?
    }
    struct Tree: Decodable, Sendable {
        let sha: String
        let tree: [TreeEntry]
        let truncated: Bool
    }

    struct Blob: Decodable, Sendable {
        let sha: String
        let content: String
        let encoding: String
    }

    struct CreatedObject: Decodable, Sendable { let sha: String }

    struct CommitListItem: Decodable, Sendable {
        let sha: String
        let commit: Detail
        struct Detail: Decodable, Sendable {
            let message: String
            let author: Author
            struct Author: Decodable, Sendable { let name: String; let date: Date }
        }
    }
}

/// One entry in a tree-creation request. `sha == nil` deletes the path (only
/// meaningful when `base_tree` is supplied).
struct TreeEntryInput: Sendable {
    var path: String
    var mode: String = "100644"
    var type: String = "blob"
    var sha: String?
}

// MARK: - Client

actor GitHubClient {
    private let token: String
    let owner: String
    let repo: String
    private let session: URLSession

    private static let apiBase = URL(string: "https://api.github.com")!

    init(token: String, owner: String, repo: String, session: URLSession = .shared) {
        self.token = token
        self.owner = owner
        self.repo = repo
        self.session = session
    }

    // MARK: URL parsing

    /// Extracts `(owner, repo)` from the URL forms a user might paste:
    /// `https://github.com/owner/repo`, `.../owner/repo.git`, an `ssh` URL,
    /// or the `owner/repo` shorthand.
    static func parseRepository(_ input: String) throws -> (owner: String, repo: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GitHubError.invalidRepositoryURL(input) }

        // Strip a scheme and host if present.
        if let range = text.range(of: "github.com") {
            text = String(text[range.upperBound...])
        } else if let schemeRange = text.range(of: "://") {
            // Some other host form; drop scheme and first path component (host).
            let afterScheme = String(text[schemeRange.upperBound...])
            if let slash = afterScheme.firstIndex(of: "/") {
                text = String(afterScheme[slash...])
            }
        }

        // Drop leading separators left by the host strip (":", "/").
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ":/ "))
        if text.lowercased().hasSuffix(".git") {
            text = String(text.dropLast(4))
        }

        let parts = text.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { throw GitHubError.invalidRepositoryURL(input) }
        let owner = parts[0]
        let repo = parts[1]
        guard !owner.isEmpty, !repo.isEmpty else { throw GitHubError.invalidRepositoryURL(input) }
        return (owner, repo)
    }

    // MARK: Endpoints

    func getRepo() async throws -> RepoInfo {
        try await get("/repos/\(owner)/\(repo)")
    }

    func listBranches() async throws -> [BranchRef] {
        try await get("/repos/\(owner)/\(repo)/branches", query: [URLQueryItem(name: "per_page", value: "100")])
    }

    func getRef(branch: String) async throws -> Ref {
        try await get("/repos/\(owner)/\(repo)/git/ref/heads/\(branch)")
    }

    func getCommit(sha: String) async throws -> Commit {
        try await get("/repos/\(owner)/\(repo)/git/commits/\(sha)")
    }

    func getTree(sha: String, recursive: Bool) async throws -> Tree {
        let query = recursive ? [URLQueryItem(name: "recursive", value: "1")] : []
        return try await get("/repos/\(owner)/\(repo)/git/trees/\(sha)", query: query)
    }

    /// Downloads a blob and returns its raw bytes.
    func getBlobData(sha: String) async throws -> Data {
        let blob: Blob = try await get("/repos/\(owner)/\(repo)/git/blobs/\(sha)")
        if blob.encoding == "base64" {
            let cleaned = blob.content.replacingOccurrences(of: "\n", with: "")
            guard let data = Data(base64Encoded: cleaned) else {
                throw GitHubError.decoding("invalid base64 blob")
            }
            return data
        }
        return Data(blob.content.utf8)
    }

    /// Creates a blob from raw bytes (base64-encoded) and returns its SHA.
    func createBlob(data: Data) async throws -> String {
        let body: [String: Any] = [
            "content": data.base64EncodedString(),
            "encoding": "base64",
        ]
        let created: CreatedObject = try await post("/repos/\(owner)/\(repo)/git/blobs", body: body)
        return created.sha
    }

    /// Creates a tree layered on top of `baseTree`. Entries with a nil sha delete
    /// their path.
    func createTree(baseTree: String, entries: [TreeEntryInput]) async throws -> String {
        let treeArray: [[String: Any]] = entries.map { entry in
            var dict: [String: Any] = [
                "path": entry.path,
                "mode": entry.mode,
                "type": entry.type,
            ]
            dict["sha"] = entry.sha ?? NSNull()
            return dict
        }
        let body: [String: Any] = ["base_tree": baseTree, "tree": treeArray]
        let created: CreatedObject = try await post("/repos/\(owner)/\(repo)/git/trees", body: body)
        return created.sha
    }

    func createCommit(message: String, tree: String, parents: [String]) async throws -> String {
        let body: [String: Any] = ["message": message, "tree": tree, "parents": parents]
        let created: CreatedObject = try await post("/repos/\(owner)/\(repo)/git/commits", body: body)
        return created.sha
    }

    /// Updates the branch ref. Throws `.nonFastForward` when GitHub rejects a
    /// non-fast-forward update (HTTP 422) and `force` is false.
    func updateRef(branch: String, sha: String, force: Bool) async throws {
        let body: [String: Any] = ["sha": sha, "force": force]
        do {
            let _: Ref = try await patch("/repos/\(owner)/\(repo)/git/refs/heads/\(branch)", body: body)
        } catch let GitHubError.server(status, _) where status == 422 {
            throw GitHubError.nonFastForward
        }
    }

    func listCommits(branch: String, limit: Int) async throws -> [CommitListItem] {
        try await get("/repos/\(owner)/\(repo)/commits", query: [
            URLQueryItem(name: "sha", value: branch),
            URLQueryItem(name: "per_page", value: String(limit)),
        ])
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(request(path, method: "GET", query: query))
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await send(request(path, method: "POST", body: body))
    }

    private func patch<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await send(request(path, method: "PATCH", body: body))
    }

    private func request(_ path: String, method: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) throws -> URLRequest {
        var components = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GitHubError.network("invalid URL") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("OrgSync", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw GitHubError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.network("no HTTP response")
        }

        try Self.mapStatus(http, data: data)

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw GitHubError.decoding(String(describing: error))
        }
    }

    /// Translates non-2xx responses into `GitHubError`.
    private static func mapStatus(_ http: HTTPURLResponse, data: Data) throws {
        guard !(200...299).contains(http.statusCode) else { return }

        let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining")
        switch http.statusCode {
        case 401:
            throw GitHubError.authenticationFailed
        case 403:
            if remaining == "0" {
                let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
                    .flatMap(Double.init)
                    .map { Date(timeIntervalSince1970: $0) }
                throw GitHubError.rateLimited(resetDate: reset)
            }
            throw GitHubError.authenticationFailed
        case 404:
            throw GitHubError.notFound
        case 429:
            throw GitHubError.rateLimited(resetDate: nil)
        default:
            let message = Self.errorMessage(from: data) ?? "unexpected status"
            throw GitHubError.server(status: http.statusCode, message: message)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        struct APIError: Decodable { let message: String? }
        return (try? JSONDecoder().decode(APIError.self, from: data))?.message
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
