//
//  FolderView.swift
//  OrgSync
//
//  Reusable directory browser used at every level of the Notes hierarchy.
//  Lists folders and `.org` files with native list styling, swipe actions
//  (favorite / rename / delete), filename search, a favorites section at the
//  root, and a toolbar affordance for creating new notes and folders.
//

import SwiftUI

struct FolderView: View {
    /// Directory this browser lists.
    let directory: URL
    /// Navigation title.
    let title: String
    /// Only the repo root shows the global Favorites section.
    let isRoot: Bool

    @Environment(RepoStore.self) private var repo
    @Environment(FavoritesStore.self) private var favorites
    @Environment(SyncEngine.self) private var sync: SyncEngine?
    @Environment(RemindersSyncEngine.self) private var reminders: RemindersSyncEngine?

    @State private var searchText = ""
    @State private var sortBy: Sort = .name
    @State private var showGitCommands = false

    // Create dialogs
    @State private var showNewNote = false
    @State private var showNewFolder = false
    @State private var newName = ""

    // Rename dialog
    @State private var renameTarget: FileItem?
    @State private var renameText = ""

    // Delete confirmation
    @State private var deleteTarget: FileItem?

    /// Populated on appear and on repo changes: conflictCopies() walks the
    /// whole repo on disk, so it must not run in `body` on every re-render.
    @State private var conflicts: [SyncEngine.ConflictCopy] = []

    var body: some View {
        List {
            if searchText.isEmpty {
                if isRoot, sync != nil {
                    if !conflicts.isEmpty {
                        Section {
                            NavigationLink {
                                ConflictResolutionView()
                            } label: {
                                Label("Resolve \(conflicts.count) Sync Conflict\(conflicts.count == 1 ? "" : "s")",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .accessibilityIdentifier("notes.resolveConflicts")
                            .accessibilityHint("Choose the local or remote version for each conflicted file.")
                        }
                    }
                }
                if isRoot {
                    let favItems = favoriteItems()
                    if !favItems.isEmpty {
                        Section("Favorites") {
                            ForEach(favItems) { row($0) }
                        }
                    }
                }
                Section {
                    let items = sorted(repo.contents(of: directory))
                    if items.isEmpty {
                        ContentUnavailableView("No Notes", systemImage: "note.text",
                                               description: Text("Use the + button to create a note or folder."))
                    } else {
                        ForEach(items) { row($0) }
                    }
                } footer: {
                    if isRoot, let sync, sync.isConnected {
                        lastSyncedCaption(sync)
                    }
                }
            } else {
                let results = sorted(repo.search(searchText, under: directory))
                if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(results) { row($0.item, snippet: $0.snippet) }
                }
            }
        }
        .navigationTitle(title)
        .accessibilityIdentifier(isRoot ? "notes.screen" : "folder.screen")
        .navigationBarTitleDisplayMode(.inline)
        // iOS 27 draws a solid bar with a hard cutoff on scroll; keep the
        // pre-27 translucent look.
        .toolbarBackground(.hidden, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search notes")
        .refreshableIfRoot(isRoot: isRoot, sync: sync, reminders: reminders, repo: repo)
        .toolbar {
            if isRoot, let sync {
                ToolbarItem(placement: .topBarLeading) {
                    syncMenu(sync)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortBy) {
                        ForEach(Sort.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                .accessibilityLabel("Sort notes")
                .accessibilityHint("Choose alphabetical or most-recent-first sorting.")
                .accessibilityIdentifier("notes.sort")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        newName = ""
                        showNewNote = true
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    Button {
                        newName = ""
                        showNewFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityHint("Create a new note or folder.")
                .accessibilityIdentifier("notes.add")
            }
        }
        .task {
            if isRoot, let sync { conflicts = sync.conflictCopies() }
        }
        .onChange(of: repo.revision) { _, _ in
            if isRoot, let sync { conflicts = sync.conflictCopies() }
        }
        .alert("New Note", isPresented: $showNewNote) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Create") { repo.createNote(named: newName, in: directory) }
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Create") { repo.createFolder(named: newName, in: directory) }
        }
        .alert("Rename", isPresented: renameIsPresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") { commitRename() }
        }
        .confirmationDialog(
            deleteTarget.map { "Delete “\($0.displayName)”?" } ?? "Delete?",
            isPresented: deleteIsPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = deleteTarget { performDelete(item) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget?.isDirectory == true
                 ? "The folder and every note inside it are deleted permanently. Unpushed changes cannot be recovered."
                 : "The note is deleted permanently. Unpushed changes cannot be recovered.")
        }
        .sheet(isPresented: $showGitCommands) {
            GitCommandPaletteView()
        }
    }

    private enum Sort: String, CaseIterable, Identifiable { case name, recent; var id: String { rawValue }; var title: String { self == .name ? "Name" : "Most Recent" } }
    private func sorted(_ items: [FileItem]) -> [FileItem] {
        sortBy == .name ? items : items.sorted { $0.modifiedDate > $1.modifiedDate }
    }
    private func sorted(_ results: [RepoStore.SearchResult]) -> [RepoStore.SearchResult] {
        sortBy == .name ? results : results.sorted { $0.item.modifiedDate > $1.item.modifiedDate }
    }

    // MARK: - Sync UI

    @ViewBuilder
    private func syncMenu(_ sync: SyncEngine) -> some View {
        Button {
            showGitCommands = true
        } label: {
            if sync.phase.isBusy {
                ProgressView()
            } else {
                Image(systemName: "arrow.triangle.branch")
                    // Persistent failure indicator: stays until the error is
                    // dismissed, so a missed alert isn't a silently lost sync.
                    .overlay(alignment: .topTrailing) {
                        if sync.lastError != nil {
                            Circle().fill(.red).frame(width: 7, height: 7).offset(x: 3, y: -2)
                        }
                    }
            }
        }
        .disabled(sync.phase.isBusy)
        .accessibilityValue(sync.lastError != nil ? "Last sync failed" : "")
        .accessibilityLabel("Git commands")
        .accessibilityHint("Open Pull, Stage, Commit, Push, and Sync commands.")
        .accessibilityIdentifier("notes.gitCommands")
    }

    @ViewBuilder
    private func lastSyncedCaption(_ sync: SyncEngine) -> some View {
        if case let .syncing(label) = sync.phase {
            Text(label)
        } else if let date = sync.lastSyncDate {
            Text("Last synced \(date.formatted(.relative(presentation: .named)))")
        } else {
            Text("Not synced yet")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ item: FileItem, snippet: String? = nil) -> some View {
        NavigationLink(value: item) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                    if let snippet {
                        Text(highlighted(snippet))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !item.isDirectory {
                        Text(item.modifiedDate, format: .dateTime.year().month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: item.isDirectory ? "folder" : "doc.text")
                    .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
            }
        }
        .accessibilityIdentifier("note.row.\(item.relativePath)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.isDirectory ? "Folder, \(item.displayName)" : "Note, \(item.displayName)")
        .accessibilityValue(item.isDirectory ? "Folder" : "Modified \(item.modifiedDate.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityHint(item.isDirectory ? "Double tap to open folder." : "Double tap to open note. Swipe right to favorite; swipe left for rename and delete.")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                beginRename(item)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !item.isDirectory {
                Button {
                    favorites.toggle(item)
                } label: {
                    let isFav = favorites.isFavorite(item)
                    Label(isFav ? "Unfavorite" : "Favorite",
                          systemImage: isFav ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
        }
    }

    /// Bolds every occurrence of the current search term in a snippet.
    private func highlighted(_ snippet: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return attributed }
        var searchStart = attributed.startIndex
        while let range = attributed[searchStart...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].font = .caption.bold()
            attributed[range].foregroundColor = .primary
            searchStart = range.upperBound
        }
        return attributed
    }

    // MARK: - Favorites

    private func favoriteItems() -> [FileItem] {
        favorites.favorites
            .compactMap { repo.item(forRelativePath: $0) }
            .filter { !$0.isDirectory }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Mutations

    /// Deleting is permanent (no trash, and unpushed edits are unrecoverable),
    /// so folders and notes with content require confirmation. Only an empty
    /// note deletes immediately.
    private func delete(_ item: FileItem) {
        let isEmptyNote = !item.isDirectory
            && repo.text(of: item).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmptyNote {
            performDelete(item)
        } else {
            deleteTarget = item
        }
    }

    private func performDelete(_ item: FileItem) {
        if repo.delete(item) {
            favorites.remove(pathOrPrefix: item.relativePath)
        }
    }

    private var deleteIsPresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func beginRename(_ item: FileItem) {
        renameText = item.displayName
        renameTarget = item
    }

    private func commitRename() {
        guard let item = renameTarget else { return }
        if let newPath = repo.rename(item, to: renameText) {
            favorites.updatePath(from: item.relativePath, to: newPath)
        }
        renameTarget = nil
    }
}

private extension View {
    /// Adds pull-to-refresh that runs a full sync, but only at the repo root and
    /// only when a repository is connected.
    @ViewBuilder
    func refreshableIfRoot(isRoot: Bool, sync: SyncEngine?, reminders: RemindersSyncEngine?, repo: RepoStore) -> some View {
        if isRoot, let sync, sync.isConnected {
            self.refreshable { await sync.syncNow(); await reminders?.sync(repo: repo) }
        } else {
            self
        }
    }
}

#Preview {
    let repo = RepoStore()
    let settings = SettingsStore()
    return NavigationStack {
        FolderView(directory: repo.repoURL, title: "Notes", isRoot: true)
            .environment(repo)
            .environment(FavoritesStore())
            .environment(SyncEngine(repo: repo, settings: settings))
    }
}
