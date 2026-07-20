//
//  NotesView.swift
//  OrgSync
//
//  Notes tab: a hierarchical browser over the local repo mirror. This view owns
//  the NavigationStack and the single destination that recursively pushes
//  folders (as further browsers) and org files (as note detail views).
//

import SwiftUI

struct NotesView: View {
    @Environment(RepoStore.self) private var repo
    @Binding var openNotePath: String?
    @State private var navigationPath: [FileItem] = []
    @State private var missingNoteName: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            FolderView(directory: repo.repoURL, title: "Notes", isRoot: true)
                .navigationDestination(for: FileItem.self) { item in
                    if item.isDirectory {
                        FolderView(directory: item.url, title: item.displayName, isRoot: false)
                    } else {
                        NoteDetailView(item: item)
                    }
                }
        }
        .onChange(of: openNotePath) { _, path in
            guard let path else { return }
            openNotePath = nil
            if let item = repo.item(forRelativePath: path), !item.isDirectory {
                navigationPath = [item]
            } else {
                // A widget or link can point at a note that was since renamed
                // or deleted — say so instead of silently landing on the root.
                missingNoteName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            }
        }
        .alert("Note Not Found", isPresented: Binding(
            get: { missingNoteName != nil },
            set: { if !$0 { missingNoteName = nil } }
        )) {
            Button("OK", role: .cancel) { missingNoteName = nil }
        } message: {
            Text("“\(missingNoteName ?? "")” may have been renamed or deleted.")
        }
    }
}

#Preview {
    NotesView(openNotePath: .constant(nil))
        .environment(RepoStore())
        .environment(FavoritesStore())
}
