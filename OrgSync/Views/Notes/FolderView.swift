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
    @State private var syncErrorShown = false

    // Create dialogs
    @State private var showNewNote = false
    @State private var showNewFolder = false
    @State private var newName = ""

    // Rename dialog
    @State private var renameTarget: FileItem?
    @State private var renameText = ""

    var body: some View {
        List {
            if searchText.isEmpty {
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
                    ForEach(results) { row($0) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .searchable(text: $searchText, prompt: "Search notes")
        .refreshableIfRoot(isRoot: isRoot, sync: sync, reminders: reminders, repo: repo)
        .toolbar {
            if isRoot, let sync, sync.isConnected {
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
            }
        }
        .onChange(of: syncError(sync)) { _, newValue in
            syncErrorShown = newValue != nil
        }
        .alert("Sync Failed", isPresented: $syncErrorShown) {
            Button("OK", role: .cancel) { sync?.lastError = nil }
        } message: {
            Text(syncError(sync) ?? "")
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
    }

    private enum Sort: String, CaseIterable, Identifiable { case name, recent; var id: String { rawValue }; var title: String { self == .name ? "Name" : "Most Recent" } }
    private func sorted(_ items: [FileItem]) -> [FileItem] {
        sortBy == .name ? items : items.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    // MARK: - Sync UI

    @ViewBuilder
    private func syncMenu(_ sync: SyncEngine) -> some View {
        Menu {
            Button {
                Task { await sync.syncNow(); await reminders?.sync(repo: repo); repo.refresh() }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(sync.phase.isBusy)
            Button {
                Task { await sync.pullNow(); await reminders?.sync(repo: repo); repo.refresh() }
            } label: {
                Label("Pull", systemImage: "arrow.down.circle")
            }
            .disabled(sync.phase.isBusy)
            Button {
                Task { await sync.pushNow(); await reminders?.sync(repo: repo); repo.refresh() }
            } label: {
                Label("Commit & Push", systemImage: "arrow.up.circle")
            }
            .disabled(sync.phase.isBusy)
            Divider()
            if !sync.conflictCopies().isEmpty {
                NavigationLink {
                    ConflictResolutionView()
                } label: {
                    Label("Resolve Conflicts", systemImage: "exclamationmark.triangle")
                }
            }
            NavigationLink {
                CommitLogView()
            } label: {
                Label("Commit Log", systemImage: "clock.arrow.circlepath")
            }
        } label: {
            if sync.phase.isBusy {
                ProgressView()
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .accessibilityLabel("Sync")
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

    private func syncError(_ sync: SyncEngine?) -> String? {
        sync?.lastError
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ item: FileItem) -> some View {
        NavigationLink(value: item) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                    if !item.isDirectory {
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

    // MARK: - Favorites

    private func favoriteItems() -> [FileItem] {
        favorites.favorites
            .compactMap { repo.item(forRelativePath: $0) }
            .filter { !$0.isDirectory }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Mutations

    private func delete(_ item: FileItem) {
        if repo.delete(item) {
            favorites.remove(pathOrPrefix: item.relativePath)
        }
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
