//
//  FakeGitHub.swift
//  OrgSyncTests
//
//  An in-memory GitHub Git Data API served through a URLProtocol, so SyncWorker
//  flows (connect/pull/commit/push) can be exercised end-to-end against the real
//  GitHubClient without a network. Each FakeGitHubRepo registers itself under a
//  unique owner/repo pair, so suites can run in parallel.
//

import Foundation
@testable import OrgSync

/// One fake remote repository: refs, commits, trees, and blobs behind a lock.
final class FakeGitHubRepo: @unchecked Sendable {
    let owner = "fake"
    let repo: String

    private let lock = NSLock()
    private var refs: [String: String] = [:]
    private var commits: [String: (tree: String, parents: [String], message: String)] = [:]
    /// tree SHA -> (path -> blob SHA)
    private var trees: [String: [String: String]] = [:]
    private var blobs: [String: Data] = [:]
    private var objectCounter = 0

    init() {
        repo = "repo-\(UUID().uuidString)"
        FakeGitHubProtocol.register(self, key: "\(owner)/\(repo)")
    }

    func makeClient() -> GitHubClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeGitHubProtocol.self]
        return GitHubClient(token: "test-token", owner: owner, repo: repo,
                            session: URLSession(configuration: config))
    }

    // MARK: Test-facing helpers

    /// Commits `changes` on top of the current head of `branch` (a nil data
    /// value deletes the path) and advances the ref. Returns the commit SHA.
    @discardableResult
    func seedCommit(branch: String, changes: [String: Data?], message: String = "seed") -> String {
        lock.lock(); defer { lock.unlock() }
        let parent = refs[branch]
        var files = parent.flatMap { commits[$0].map { trees[$0.tree] ?? [:] } } ?? [:]
        for (path, data) in changes {
            if let data { blobs[GitBlob.sha1(for: data)] = data; files[path] = GitBlob.sha1(for: data) }
            else { files.removeValue(forKey: path) }
        }
        let treeSHA = nextSHA("tree")
        trees[treeSHA] = files
        let commitSHA = nextSHA("commit")
        commits[commitSHA] = (tree: treeSHA, parents: parent.map { [$0] } ?? [], message: message)
        refs[branch] = commitSHA
        return commitSHA
    }

    func headSHA(branch: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return refs[branch]
    }

    /// Path -> content at the current head of `branch`.
    func filesAtHead(branch: String) -> [String: Data] {
        lock.lock(); defer { lock.unlock() }
        guard let head = refs[branch], let commit = commits[head], let tree = trees[commit.tree] else { return [:] }
        return tree.compactMapValues { blobs[$0] }
    }

    func commitMessage(sha: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return commits[sha]?.message
    }

    // MARK: Request handling (called by the protocol)

    fileprivate func handle(method: String, gitPath: [String], body: Data?) -> (status: Int, json: Any) {
        lock.lock(); defer { lock.unlock() }
        switch (method, gitPath.first) {
        case ("GET", "ref"):
            // ref/heads/<branch...>
            let branch = gitPath.dropFirst(2).joined(separator: "/")
            guard let sha = refs[branch] else { return notFound() }
            return (200, refJSON(branch: branch, sha: sha))
        case ("GET", "commits"):
            guard gitPath.count == 2, let commit = commits[gitPath[1]] else { return notFound() }
            return (200, ["sha": gitPath[1], "tree": ["sha": commit.tree], "message": commit.message])
        case ("GET", "trees"):
            guard gitPath.count == 2, let tree = trees[gitPath[1]] else { return notFound() }
            let entries: [[String: Any]] = tree.map { path, blobSHA in
                ["path": path, "mode": "100644", "type": "blob", "sha": blobSHA,
                 "size": blobs[blobSHA]?.count ?? 0]
            }
            return (200, ["sha": gitPath[1], "tree": entries, "truncated": false])
        case ("GET", "blobs"):
            guard gitPath.count == 2, let data = blobs[gitPath[1]] else { return notFound() }
            return (200, ["sha": gitPath[1], "content": data.base64EncodedString(), "encoding": "base64"])
        case ("POST", "blobs"):
            guard let json = decode(body), let content = json["content"] as? String,
                  let data = Data(base64Encoded: content) else { return badRequest() }
            let sha = GitBlob.sha1(for: data)
            blobs[sha] = data
            return (201, ["sha": sha])
        case ("POST", "trees"):
            guard let json = decode(body), let baseTree = json["base_tree"] as? String,
                  var files = trees[baseTree], let entries = json["tree"] as? [[String: Any]] else { return badRequest() }
            for entry in entries {
                guard let path = entry["path"] as? String else { return badRequest() }
                if let sha = entry["sha"] as? String { files[path] = sha }
                else { files.removeValue(forKey: path) }
            }
            let sha = nextSHA("tree")
            trees[sha] = files
            return (201, ["sha": sha])
        case ("POST", "commits"):
            guard let json = decode(body), let tree = json["tree"] as? String,
                  let message = json["message"] as? String,
                  let parents = json["parents"] as? [String] else { return badRequest() }
            let sha = nextSHA("commit")
            commits[sha] = (tree: tree, parents: parents, message: message)
            return (201, ["sha": sha])
        case ("PATCH", "refs"):
            let branch = gitPath.dropFirst(2).joined(separator: "/")
            guard let json = decode(body), let sha = json["sha"] as? String,
                  let force = json["force"] as? Bool else { return badRequest() }
            if let current = refs[branch], !force, !isAncestor(current, of: sha) {
                return (422, ["message": "Update is not a fast forward"])
            }
            refs[branch] = sha
            return (200, refJSON(branch: branch, sha: sha))
        default:
            return notFound()
        }
    }

    private func isAncestor(_ ancestor: String, of sha: String) -> Bool {
        var frontier = [sha]
        var seen = Set<String>()
        while let current = frontier.popLast() {
            if current == ancestor { return true }
            guard seen.insert(current).inserted, let commit = commits[current] else { continue }
            frontier.append(contentsOf: commit.parents)
        }
        return false
    }

    private func refJSON(branch: String, sha: String) -> [String: Any] {
        ["ref": "refs/heads/\(branch)", "object": ["sha": sha, "type": "commit"]]
    }

    private func decode(_ body: Data?) -> [String: Any]? {
        body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private func nextSHA(_ kind: String) -> String {
        objectCounter += 1
        return "\(kind)-\(objectCounter)-\(repo.suffix(8))"
    }

    private func notFound() -> (Int, Any) { (404, ["message": "Not Found"]) }
    private func badRequest() -> (Int, Any) { (400, ["message": "Bad Request"]) }
}

/// Routes api.github.com requests to the registered FakeGitHubRepo.
final class FakeGitHubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var registry: [String: FakeGitHubRepo] = [:]

    static func register(_ repo: FakeGitHubRepo, key: String) {
        lock.lock(); defer { lock.unlock() }
        registry[key] = repo
    }

    private static func repo(for key: String) -> FakeGitHubRepo? {
        lock.lock(); defer { lock.unlock() }
        return registry[key]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // Expected path: /repos/<owner>/<repo>/git/<...>
        let components = (request.url?.path ?? "").split(separator: "/").map(String.init)
        guard components.count >= 5, components[0] == "repos", components[3] == "git",
              let repo = Self.repo(for: "\(components[1])/\(components[2])") else {
            respond(status: 404, json: ["message": "Not Found"])
            return
        }
        let result = repo.handle(method: request.httpMethod ?? "GET",
                                 gitPath: Array(components.dropFirst(4)),
                                 body: bodyData())
        respond(status: result.status, json: result.json)
    }

    private func bodyData() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private func respond(status: Int, json: Any) {
        guard let url = request.url,
              let data = try? JSONSerialization.data(withJSONObject: json),
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
