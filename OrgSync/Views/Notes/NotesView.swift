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
            guard let path, let item = repo.item(forRelativePath: path), !item.isDirectory else { return }
            navigationPath = [item]
            openNotePath = nil
        }
    }
}

#Preview {
    NotesView(openNotePath: .constant(nil))
        .environment(RepoStore())
        .environment(FavoritesStore())
}
