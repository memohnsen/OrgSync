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

    @State private var searchText = ""

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
                    let items = repo.contents(of: directory)
                    if items.isEmpty {
                        ContentUnavailableView("No Notes", systemImage: "note.text",
                                               description: Text("Use the + button to create a note or folder."))
                    } else {
                        ForEach(items) { row($0) }
                    }
                }
            } else {
                let results = repo.search(searchText, under: directory)
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
        .toolbar {
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

#Preview {
    NavigationStack {
        FolderView(directory: RepoStore().repoURL, title: "Notes", isRoot: true)
            .environment(RepoStore())
            .environment(FavoritesStore())
    }
}
