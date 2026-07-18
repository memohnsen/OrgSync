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
    /// Root of the local repo mirror.
    let repoURL: URL

    /// Bumped on every mutation so SwiftUI views that read it during `body`
    /// recompute their (non-observable) FileManager listings.
    private(set) var revision = 0

    private let fileManager = FileManager.default
    private var mutationBatchDepth = 0
    private var mutationPending = false

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        repoURL = documents.appendingPathComponent("repo", isDirectory: true)
        bootstrap()
        AgendaSnapshotWriter.write(repo: self)
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

    /// All `.org` files anywhere under `directory` whose filename or text
    /// contents match `query`. Used for recursive full-text note search.
    func search(_ query: String, under directory: URL) -> [FileItem] {
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

        var results: [FileItem] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            guard !isDirectory, url.pathExtension.lowercased() == "org" else { continue }
            let matchesName = url.lastPathComponent.localizedCaseInsensitiveContains(trimmed)
            let matchesText = (try? String(contentsOf: url, encoding: .utf8))?
                .localizedCaseInsensitiveContains(trimmed) ?? false
            guard matchesName || matchesText else { continue }
            results.append(FileItem(
                url: url,
                relativePath: relativePath(for: url),
                isDirectory: false,
                modifiedDate: values?.contentModificationDate ?? .distantPast
            ))
        }
        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
        return enumerator.compactMap { $0 as? URL }.compactMap { url in
            guard url.pathExtension.lowercased() == "org",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return item(forRelativePath: relativePath(for: url))
        }.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
    }

    /// Open and completed TODOs across the full local mirror.
    func allTodoItems() -> [OrgTodoItem] {
        allOrgFiles().flatMap { document(of: $0).todoItems(filePath: $0.relativePath) }
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

    /// Raw text contents of a file.
    func text(of item: FileItem) -> String {
        (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
    }

    /// Parse a file into an `OrgDocument`.
    func document(of item: FileItem) -> OrgDocument {
        var document = OrgParser.parse(text(of: item))
        // A document-local #+TODO remains authoritative; otherwise apply the
        // user's global preference as the default TODO vocabulary.
        let hasLocalConfig = document.keywords.contains { OrgTodoConfig.keywordNames.contains($0.key.uppercased()) }
        if !hasLocalConfig,
           let value = UserDefaults.standard.string(forKey: "settings.todo.keywords"), !value.isEmpty {
            document.todoConfig = OrgTodoConfig(sequences: [OrgTodoConfig.parseSequence(value)])
        }
        return document
    }

    /// Overwrite a file's contents with `text`. Used by the note editor and by
    /// rendered-view mutations (checkbox toggles, TODO/priority changes).
    @discardableResult
    func write(_ text: String, to item: FileItem) -> Bool {
        guard (try? text.write(to: item.url, atomically: true, encoding: .utf8)) != nil else {
            return false
        }
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
        didMutateRepo()
        return relativePath(for: destination)
    }

    /// Deletes a file or folder (folders recursively).
    @discardableResult
    func delete(_ item: FileItem) -> Bool {
        guard (try? fileManager.removeItem(at: item.url)) != nil else { return false }
        didMutateRepo()
        return true
    }

    /// Forces observing views to re-list the directory. Called after a sync
    /// writes files directly to disk (bypassing the mutation helpers above).
    func refresh() {
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

    private func bootstrap() {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: repoURL.path, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return
        }
        try? fileManager.createDirectory(at: repoURL, withIntermediateDirectories: true)
        seedSampleFiles()
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
