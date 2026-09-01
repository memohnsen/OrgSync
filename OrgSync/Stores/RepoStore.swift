//
//  RepoStore.swift
//  OrgSync
//
//  Owns the local repo mirror in Documents/repo: lists the folder hierarchy,
//  creates/renames/deletes `.org` files and folders, and seeds a small set of
//  sample files on first launch so the app is usable before git sync is set up.
//

import Foundation
import Observation

@Observable
final class RepoStore {
    /// Keeps parsing, highlighting, snapshots, and other whole-file operations
    /// within a defensible memory budget. GitHub sync uses the same limit.
    static let maxOrgFileBytes = 5 * 1024 * 1024
    static let maxOrgFiles = 10_000
    static let maxRepositoryEntries = 100_000
    static let maxIndexedTodoItems = 50_000
    static let maxSearchResults = 500

    /// Root of the local repo mirror.
    let repoURL: URL

    /// Bumped on every mutation so SwiftUI views that read it during `body`
    /// recompute their (non-observable) FileManager listings.
    private(set) var revision = 0

    private let fileManager = FileManager.default
    private var mutationBatchDepth = 0
    private var mutationPending = false

    /// Parsed-document cache keyed by repo-relative path. Avoids re-parsing every
    /// file on each `allTodoItems()` / snapshot write. Entries are invalidated on
    /// local writes and validated against file modification date + the global
    /// TODO-config signature so external (synced) changes are picked up too.
    @ObservationIgnored private var documentCache: [String: CachedDocument] = [:]

    /// Count of real parses performed (cache misses). Exposed for tests.
    @ObservationIgnored private(set) var parseCount = 0

    private struct CachedDocument {
        let modificationDate: Date
        let configSignature: String
        let document: OrgDocument
    }

    init() {
        repoURL = NotesLocation.currentRepoURL(fileManager: fileManager)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-repo") {
            try? fileManager.removeItem(at: repoURL)
        }
        bootstrap(seedsSampleContent: true)
        AgendaSnapshotWriter.write(repo: self)
    }

    /// Test seam: points the store at an explicit directory and optionally skips
    /// the first-launch sample seeding so tests control the contents.
    init(repoURL: URL, seedsSampleContent: Bool) {
        self.repoURL = repoURL
        bootstrap(seedsSampleContent: seedsSampleContent)
    }

    // MARK: - Listing

    /// Immediate children of the given directory, folders first then files,
    /// each group sorted case-insensitively by name. Only folders and `.org`
    /// files are surfaced.
    func contents(of directory: URL) -> [FileItem] {
        _ = revision // establish observation dependency for SwiftUI

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let items: [FileItem] = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            if !isDirectory && url.pathExtension.lowercased() != "org" {
                return nil
            }
            return FileItem(
                url: url,
                relativePath: relativePath(for: url),
                isDirectory: isDirectory,
                modifiedDate: values?.contentModificationDate ?? .distantPast
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// One full-text search hit: the matching file plus, when the match was in
    /// the note's text, the first matching line to show as a preview snippet.
    /// `snippet` is nil when only the filename matched.
    struct SearchResult: Identifiable {
        let item: FileItem
        let snippet: String?
        var id: FileItem.ID { item.id }
    }

    /// All `.org` files anywhere under `directory` whose filename or text
    /// contents match `query`. Used for recursive full-text note search.
    func search(_ query: String, under directory: URL) -> [SearchResult] {
        _ = revision

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [SearchResult] = []
        var scannedFiles = 0
        var scannedEntries = 0
        for case let url as URL in enumerator {
            scannedEntries += 1
            guard scannedEntries <= Self.maxRepositoryEntries else { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            guard !isDirectory, url.pathExtension.lowercased() == "org" else { continue }
            scannedFiles += 1
            guard scannedFiles <= Self.maxOrgFiles else { break }
            let item = FileItem(
                url: url,
                relativePath: relativePath(for: url),
                isDirectory: false,
                modifiedDate: values?.contentModificationDate ?? .distantPast
            )
            let matchesName = url.lastPathComponent.localizedCaseInsensitiveContains(trimmed)
            let snippet = (try? text(of: item))
                .flatMap { Self.snippet(for: trimmed, in: $0) }
            guard matchesName || snippet != nil else { continue }
            results.append(SearchResult(
                item: item,
                snippet: snippet
            ))
            if results.count == Self.maxSearchResults { break }
        }
        return results.sorted {
            $0.item.name.localizedCaseInsensitiveCompare($1.item.name) == .orderedAscending
        }
    }

    /// First line of `text` containing `query`, trimmed for display. When the
    /// match sits deep in a long line, the leading text is elided so the match
    /// stays visible in a single truncated row.
    static func snippet(for query: String, in text: String) -> String? {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            let lead = line.distance(from: line.startIndex, to: range.lowerBound)
            if lead <= 30 { return line }
            // Start a little before the match so it has context but isn't
            // pushed past the row's truncation point.
            let start = line.index(range.lowerBound, offsetBy: -20, limitedBy: line.startIndex) ?? line.startIndex
            return "…" + line[start...].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Every org file in the local mirror, using the repository's single
    /// canonical discovery and path-normalization policy.
    func allOrgFiles() -> [FileItem] {
        _ = revision
        guard let enumerator = fileManager.enumerator(
            at: repoURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var items: [FileItem] = []
        var scannedEntries = 0
        for case let url as URL in enumerator {
            scannedEntries += 1
            guard scannedEntries <= Self.maxRepositoryEntries else { break }
            guard url.pathExtension.lowercased() == "org",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let item = item(forRelativePath: relativePath(for: url)) else { continue }
            items.append(item)
            if items.count == Self.maxOrgFiles { break }
        }
        return items.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    /// Open and completed TODOs across the full local mirror.
    func allTodoItems() -> [OrgTodoItem] {
        var result: [OrgTodoItem] = []
        for item in allOrgFiles() {
            // Derived agenda/search surfaces may omit an unavailable iCloud file;
            // they never write that fallback back to disk. Mutation paths call
            // `document(of:)` directly and require a successful read.
            guard let document = try? document(of: item) else { continue }
            let remaining = Self.maxIndexedTodoItems - result.count
            guard remaining > 0 else { break }
            result.append(contentsOf: document.todoItems(
                filePath: item.relativePath,
                maxItems: remaining
            ))
        }
        return result
    }

    /// Notes that reference `item` through an org `[[wiki-link]]`, name-sorted.
    func backlinks(to item: FileItem) -> [FileItem] {
        _ = revision
        let displayName = item.displayName
        let relativePath = item.relativePath
        return allOrgFiles()
            .filter { $0.relativePath != relativePath }
            .filter { file in
                guard let text = try? text(of: file) else { return false }
                return WikiLink.targets(in: text).contains {
                    WikiLink.resolves($0, toNoteNamed: displayName, relativePath: relativePath)
                }
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Resolves a repo-relative path to a `FileItem`, if the entry still exists.
    func item(forRelativePath path: String) -> FileItem? {
        let url = repoURL.appendingPathComponent(path)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return FileItem(
            url: url,
            relativePath: path,
            isDirectory: values.isDirectory ?? false,
            modifiedDate: values.contentModificationDate ?? .distantPast
        )
    }

    /// Raw UTF-8 text contents of a file. Read failures are never converted to
    /// an empty document because mutation callers could then overwrite data.
    func text(of item: FileItem) throws -> String {
        let values = try item.url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > Self.maxOrgFileBytes {
            throw CocoaError(.fileReadTooLarge, userInfo: [
                NSFilePathErrorKey: item.url.path,
                NSLocalizedDescriptionKey: "\(item.relativePath) exceeds the 5 MB note limit.",
            ])
        }
        let data = try Data(contentsOf: item.url, options: .mappedIfSafe)
        guard data.count <= Self.maxOrgFileBytes else {
            throw CocoaError(.fileReadTooLarge, userInfo: [
                NSFilePathErrorKey: item.url.path,
                NSLocalizedDescriptionKey: "\(item.relativePath) exceeds the 5 MB note limit.",
            ])
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [NSFilePathErrorKey: item.url.path])
        }
        return text
    }

    /// Parse a file into an `OrgDocument`. Cached by path; the cache is reused
    /// only when the file's modification date and the global TODO-config
    /// signature both match the parsed entry.
    func document(of item: FileItem) throws -> OrgDocument {
        let signature = Self.configSignature()
        if let cached = documentCache[item.relativePath],
           cached.modificationDate == item.modifiedDate,
           cached.configSignature == signature {
            return cached.document
        }

        let source = try text(of: item)
        parseCount += 1
        var document = OrgParser.parse(source)
        // A document-local #+TODO remains authoritative; otherwise apply the
        // user's global preference as the default TODO vocabulary.
        let hasLocalConfig = document.keywords.contains { OrgTodoConfig.keywordNames.contains($0.key.uppercased()) }
        if !hasLocalConfig, !signature.isEmpty {
            document.todoConfig = OrgTodoConfig(sequences: [OrgTodoConfig.parseSequence(signature)])
        }
        documentCache[item.relativePath] = CachedDocument(
            modificationDate: item.modifiedDate, configSignature: signature, document: document
        )
        return document
    }

    /// Signature that distinguishes cached parses across global TODO-config
    /// changes (the only parse input outside the file itself).
    private static func configSignature() -> String {
        UserDefaults.standard.string(forKey: "settings.todo.keywords") ?? ""
    }

    /// Overwrite a file's contents with `text`. Used by the note editor and by
    /// rendered-view mutations (checkbox toggles, TODO/priority changes).
    @discardableResult
    func write(_ text: String, to item: FileItem) -> Bool {
        guard (try? text.write(to: item.url, atomically: true, encoding: .utf8)) != nil else {
            return false
        }
        // Same-second writes can share a modification date, so invalidate
        // explicitly rather than relying on the date check alone.
        documentCache[item.relativePath] = nil
        didMutateRepo()
        return true
    }

    // MARK: - Mutations

    /// Creates a new empty `.org` file with the given base name in `directory`.
    /// Returns the created item, or `nil` if it already exists / failed.
    @discardableResult
    func createNote(named rawName: String, in directory: URL) -> FileItem? {
        let base = sanitized(rawName)
        guard !base.isEmpty else { return nil }
        let fileName = base.hasSuffix(".org") ? base : base + ".org"
        let url = directory.appendingPathComponent(fileName)
        guard !fileManager.fileExists(atPath: url.path) else { return nil }

        let seed = "#+TITLE: \(base.hasSuffix(".org") ? String(base.dropLast(4)) : base)\n\n"
        guard (try? seed.write(to: url, atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        didMutateRepo()
        return item(forRelativePath: relativePath(for: url))
    }

    /// Creates a new folder with the given name in `directory`.
    @discardableResult
    func createFolder(named rawName: String, in directory: URL) -> FileItem? {
        let name = sanitized(rawName)
        guard !name.isEmpty else { return nil }
        let url = directory.appendingPathComponent(name, isDirectory: true)
        guard !fileManager.fileExists(atPath: url.path) else { return nil }
        guard (try? fileManager.createDirectory(at: url, withIntermediateDirectories: false)) != nil else {
            return nil
        }
        didMutateRepo()
        return item(forRelativePath: relativePath(for: url))
    }

    /// Renames a file or folder. For files, a missing `.org` extension is
    /// re-applied. Returns the new relative path so callers can migrate state
    /// (e.g. favorites), or `nil` on failure.
    @discardableResult
    func rename(_ item: FileItem, to rawName: String) -> String? {
        let base = sanitized(rawName)
        guard !base.isEmpty else { return nil }

        var newName = base
        if !item.isDirectory {
            newName = base.hasSuffix(".org") ? base : base + ".org"
        }

        let destination = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        guard destination != item.url else { return item.relativePath }
        guard !fileManager.fileExists(atPath: destination.path) else { return nil }
        guard (try? fileManager.moveItem(at: item.url, to: destination)) != nil else {
            return nil
        }
        // A folder rename changes every descendant's path, so clear everything;
        // a file rename only frees its own entry.
        if item.isDirectory { documentCache.removeAll() } else { documentCache[item.relativePath] = nil }
        didMutateRepo()
        return relativePath(for: destination)
    }

    /// Deletes a file or folder (folders recursively).
    @discardableResult
    func delete(_ item: FileItem) -> Bool {
        guard (try? fileManager.removeItem(at: item.url)) != nil else { return false }
        if item.isDirectory { documentCache.removeAll() } else { documentCache[item.relativePath] = nil }
        didMutateRepo()
        return true
    }

    /// Forces observing views to re-list the directory. Called after a sync
    /// writes files directly to disk (bypassing the mutation helpers above), so
    /// the entire parse cache is discarded — any file may have changed.
    func refresh() {
        documentCache.removeAll()
        didMutateRepo()
    }

    /// Coalesces a logical bulk operation into one revision bump and one widget
    /// snapshot refresh. Sync and Reminders use this when touching many files.
    func performMutationBatch(_ operation: () -> Void) {
        mutationBatchDepth += 1
        operation()
        mutationBatchDepth -= 1
        if mutationBatchDepth == 0, mutationPending {
            mutationPending = false
            publishMutation()
        }
    }

    // MARK: - Helpers

    private func didMutateRepo() {
        if mutationBatchDepth > 0 { mutationPending = true; return }
        publishMutation()
    }

    private func publishMutation() {
        revision &+= 1
        // WidgetKit reads the shared Agenda snapshot rather than the app's
        // Documents mirror. Refresh it after every local or synced mutation.
        AgendaSnapshotWriter.write(repo: self)
    }

    private func relativePath(for url: URL) -> String {
        let rootComponents = repoURL.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count,
              Array(urlComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.lastPathComponent
        }
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func sanitized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - Bootstrap / seed

    private func bootstrap(seedsSampleContent: Bool) {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: repoURL.path, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return
        }
        try? fileManager.createDirectory(at: repoURL, withIntermediateDirectories: true)
        if seedsSampleContent { seedSampleFiles() }
    }

    private func seedSampleFiles() {
        write(SeedContent.inbox, to: "inbox.org")
        write(SeedContent.projects, to: "projects.org")

        let notesDir = repoURL.appendingPathComponent("notes", isDirectory: true)
        try? fileManager.createDirectory(at: notesDir, withIntermediateDirectories: true)
        write(SeedContent.reading, to: "notes/reading.org")
    }

    private func write(_ contents: String, to relativePath: String) {
        let url = repoURL.appendingPathComponent(relativePath)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Sample `.org` documents seeded on first launch.
private enum SeedContent {
    static let inbox = """
    #+TITLE: Inbox

    * TODO Reply to Sam about the beta invite
    * TODO Buy groceries for the weekend
    * Quick capture
      Random thoughts land here before they get filed.
    """

    static let projects = """
    #+TITLE: Projects

    * TODO Launch OrgSync beta
      SCHEDULED: <2026-07-25 Sat>
    ** TODO Finish the GitHub sync engine
    ** TODO Write the onboarding flow
    ** DONE Design the app shell
    * TODO Publish documentation site
      DEADLINE: <2026-07-30 Thu>
    * Website redesign
    ** TODO Draft the homepage copy
       SCHEDULED: <2026-07-20 Mon>
    ** TODO Pick an accent color
    """

    static let reading = """
    #+TITLE: Reading List

    * Books
    ** TODO The Pragmatic Programmer
    ** DONE Clean Code
    * Articles
      - Org mode for beginners
      - SwiftUI navigation patterns
      - Building a git client in Swift
    """
}
