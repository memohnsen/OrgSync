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

    var body: some View {
        NavigationStack {
            FolderView(directory: repo.repoURL, title: "Notes", isRoot: true)
                .navigationDestination(for: FileItem.self) { item in
                    if item.isDirectory {
                        FolderView(directory: item.url, title: item.displayName, isRoot: false)
                    } else {
                        NoteDetailView(item: item)
                    }
                }
        }
    }
}

#Preview {
    NotesView()
        .environment(RepoStore())
        .environment(FavoritesStore())
}
