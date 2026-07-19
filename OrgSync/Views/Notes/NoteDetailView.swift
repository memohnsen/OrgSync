//
//  NoteDetailView.swift
//  OrgSync
//
//  Note detail: a rendered, foldable org document with tappable checkboxes and
//  TODO/priority quick actions, plus an Edit mode that swaps in a syntax-
//  highlighted plain-text editor. Reader mutations and editor changes both
//  persist to disk through `RepoStore` (debounced autosave in edit mode; on-exit
//  and on-disappear flushes guarantee nothing is lost).
//

import SwiftUI

struct NoteDetailView: View {
    let item: FileItem

    @Environment(RepoStore.self) private var repo
    @Environment(FavoritesStore.self) private var favorites
    @Environment(SettingsStore.self) private var settings

    @State private var document = OrgDocument()
    @State private var isEditing = false
    @State private var editText = ""
    @State private var collapsed: Set<[Int]> = []
    @State private var autosaveTask: Task<Void, Never>?
    @State private var loaded = false
    @State private var originalEditText = ""
    /// The file text this view last loaded from or wrote to disk. Lets a repo
    /// revision bump (background pull, Reminders sync) be recognized as an
    /// external change so the stale in-memory document isn't written back
    /// over it by the next reader mutation.
    @State private var diskText = ""
    @State private var backlinks: [OrgReaderView.BacklinkRef] = []
    @State private var toolbarCommands = OrgEditorToolbarPreferences.load()
    @State private var isCustomizingToolbar = false

    var body: some View {
        Group {
            if isEditing {
                OrgSourceEditor(
                    text: $editText,
                    commands: toolbarCommands,
                    todoKeywords: Set(OrgTodoStatusConfiguration.statuses(from: settings.todoKeywords).map(\.name)),
                    isShowingToolbarCustomization: $isCustomizingToolbar
                )
                    .ignoresSafeArea(.container, edges: .bottom)
                    .onChange(of: editText) { _, _ in scheduleAutosave() }
            } else {
                OrgReaderView(document: document, collapsed: $collapsed, actions: readerActions,
                              backlinks: backlinks,
                              onOpenBacklink: { AppServices.requestOpen(tab: "notes", note: $0.relativePath) })
            }
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(item)
                } label: {
                    Image(systemName: favorites.isFavorite(item) ? "star.fill" : "star")
                }
                .accessibilityLabel(favorites.isFavorite(item) ? "Unfavorite" : "Favorite")
                .accessibilityHint("Adds or removes this note from Favorites.")
                .accessibilityIdentifier("note.favorite")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Done") { exitEditMode() }
                        .accessibilityIdentifier("note.doneEditing")
                } else {
                    Button("Edit") { enterEditMode() }
                        .accessibilityHint("Edit this note as org source text.")
                        .accessibilityIdentifier("note.edit")
                }
            }
        }
        .task(id: item.id) { loadFromDisk() }
        .onChange(of: repo.revision) { _, _ in reloadIfDiskChanged() }
        .onDisappear { flushOnDisappear() }
        .onChange(of: toolbarCommands) { _, commands in
            OrgEditorToolbarPreferences.save(commands)
        }
        .sheet(isPresented: $isCustomizingToolbar) {
            OrgEditorToolbarCustomizationView(commands: $toolbarCommands)
        }
    }

    // MARK: - Loading & saving

    private func loadFromDisk() {
        guard !loaded else { return }
        diskText = repo.text(of: item)
        document = repo.document(of: item)
        refreshBacklinks()
        loaded = true
    }

    private func refreshBacklinks() {
        backlinks = repo.backlinks(to: item).map {
            OrgReaderView.BacklinkRef(relativePath: $0.relativePath, title: $0.displayName)
        }
    }

    /// Adopts changes another writer (pull, Reminders sync) made to this file
    /// while it is open, so reader mutations and the editor don't serialize a
    /// stale document over them. An edit buffer with unsaved changes is kept:
    /// those keystrokes win as an ordinary local change.
    private func reloadIfDiskChanged() {
        guard loaded else { return }
        let current = repo.text(of: item)
        guard current != diskText else { return }
        if isEditing {
            guard editText == originalEditText else { return }
            editText = current
            originalEditText = current
        }
        diskText = current
        document = repo.document(of: item)
        refreshBacklinks()
    }

    private func enterEditMode() {
        editText = document.serialize()
        originalEditText = editText
        withAnimation { isEditing = true }
    }

    private func exitEditMode() {
        autosaveTask?.cancel()
        document = OrgParser.parse(editText)
        saveEditedTextAndRecordReviewIfNeeded()
        withAnimation { isEditing = false }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = editText
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                if repo.write(snapshot, to: item) { diskText = snapshot }
            }
        }
    }

    private func flushOnDisappear() {
        autosaveTask?.cancel()
        if isEditing {
            saveEditedTextAndRecordReviewIfNeeded()
        }
    }

    private func saveEditedTextAndRecordReviewIfNeeded() {
        let changed = editText != originalEditText
        guard repo.write(editText, to: item) else { return }
        diskText = editText
        originalEditText = editText
        if changed { AppReviewPrompter.recordEditedNote(path: item.relativePath) }
    }

    // MARK: - Reader mutations

    private var readerActions: OrgReaderActions {
        OrgReaderActions(
            cycleTodo: { path in
                cycleTodo(at: path)
            },
            setTodo: { path, keyword in
                setTodo(at: path, keyword: keyword)
            },
            setPriority: { path, priority in
                mutateHeadline(at: path) { $0.setPriority(priority) }
            },
            toggleCheckbox: { path, contentIndex, itemPath in
                var updated = document
                updated.toggleCheckbox(headlinePath: path, contentIndex: contentIndex, itemPath: itemPath)
                commit(updated)
            },
            togglePreambleCheckbox: { contentIndex, itemPath in
                var updated = document
                updated.togglePreambleCheckbox(contentIndex: contentIndex, itemPath: itemPath)
                commit(updated)
            }
        )
    }

    private func mutateHeadline(at path: [Int], _ transform: (inout OrgHeadline) -> Void) {
        var updated = document
        updated.mutateHeadline(at: path, transform)
        commit(updated)
    }

    private func cycleTodo(at path: [Int]) {
        guard let todo = todoItem(at: path) else { return }
        let sequence = document.todoConfig.sequence(for: todo.keyword) ?? document.todoConfig.sequences.first
        guard let sequence, let current = sequence.all.firstIndex(of: todo.keyword) else { return }
        let next = sequence.all[(current + 1) % sequence.all.count]
        setTodo(at: path, keyword: next)
    }

    private func setTodo(at path: [Int], keyword: String?) {
        guard let todo = todoItem(at: path) else { return }
        if OrgTodoStatusPalette.isCompleted(keyword), !todo.isDone {
            guard TaskCompletionService.complete(todo, repo: repo, settings: settings) else { return }
            let current = repo.text(of: item)
            diskText = current
            document = repo.document(of: item)
            return
        }
        mutateHeadline(at: path) { $0.setTodoKeyword(keyword, config: document.todoConfig) }
    }

    private func todoItem(at path: [Int]) -> OrgTodoItem? {
        func headline(_ headlines: [OrgHeadline], path: ArraySlice<Int>) -> OrgHeadline? {
            guard let index = path.first, headlines.indices.contains(index) else { return nil }
            let current = headlines[index]
            return path.count == 1 ? current : headline(current.children, path: path.dropFirst())
        }
        guard let target = headline(document.headlines, path: ArraySlice(path)) else { return nil }
        return document.todoItems(filePath: item.relativePath).first {
            document.headline(at: $0.outline)?.id == target.id
        }
    }

    /// Adopt a mutated document and persist it.
    private func commit(_ updated: OrgDocument) {
        document = updated
        let text = updated.serialize()
        if repo.write(text, to: item) { diskText = text }
    }
}

#Preview {
    NavigationStack {
        NoteDetailView(item: FileItem(
            url: URL(fileURLWithPath: "/tmp/sample.org"),
            relativePath: "sample.org",
            isDirectory: false,
            modifiedDate: .now
        ))
        .environment(RepoStore())
        .environment(FavoritesStore())
    }
}
