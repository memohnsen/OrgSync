//
//  NoteDetailView.swift
//  OrgSync
//
//  Placeholder note detail: shows the raw text of an `.org` file. Phase 3
//  replaces this with a rendered, foldable, editable org document view.
//

import SwiftUI

struct NoteDetailView: View {
    let item: FileItem

    @Environment(RepoStore.self) private var repo
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        ScrollView {
            Text(repo.text(of: item))
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    favorites.toggle(item)
                } label: {
                    let isFav = favorites.isFavorite(item)
                    Image(systemName: isFav ? "star.fill" : "star")
                }
                .accessibilityLabel(favorites.isFavorite(item) ? "Unfavorite" : "Favorite")
            }
        }
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
