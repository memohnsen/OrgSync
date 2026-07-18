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

    @State private var document = OrgDocument()
    @State private var isEditing = false
    @State private var editText = ""
    @State private var collapsed: Set<[Int]> = []
    @State private var autosaveTask: Task<Void, Never>?
    @State private var loaded = false
    @State private var originalEditText = ""
    @State private var toolbarCommands = OrgEditorToolbarPreferences.load()
    @State private var isCustomizingToolbar = false

    var body: some View {
        Group {
            if isEditing {
                OrgSourceEditor(
                    text: $editText,
                    commands: toolbarCommands,
                    isShowingToolbarCustomization: $isCustomizingToolbar
                )
                    .ignoresSafeArea(.container, edges: .bottom)
                    .onChange(of: editText) { _, _ in scheduleAutosave() }
            } else {
                OrgReaderView(document: document, collapsed: $collapsed, actions: readerActions)
            }
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
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
        document = repo.document(of: item)
        loaded = true
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
            await MainActor.run { _ = repo.write(snapshot, to: item) }
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
        originalEditText = editText
        if changed { AppReviewPrompter.recordEditedNote(path: item.relativePath) }
    }

    // MARK: - Reader mutations

    private var readerActions: OrgReaderActions {
        OrgReaderActions(
            cycleTodo: { path in
                mutateHeadline(at: path) { $0.cycleTodo(config: document.todoConfig) }
            },
            setTodo: { path, keyword in
                mutateHeadline(at: path) { $0.setTodoKeyword(keyword, config: document.todoConfig) }
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

    /// Adopt a mutated document and persist it.
    private func commit(_ updated: OrgDocument) {
        document = updated
        repo.write(updated.serialize(), to: item)
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
