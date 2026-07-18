//
//  RootView.swift
//  OrgSync
//
//  Top-level tab shell: Notes, Agenda, Settings. Owns the app's shared stores
//  and injects them into the environment for the tab content to consume.
//

import SwiftUI

struct RootView: View {
    @State private var repo = RepoStore()
    @State private var favorites = FavoritesStore()
    @State private var settings = SettingsStore()

    var body: some View {
        TabView {
            Tab("Notes", systemImage: "note.text") {
                NotesView()
            }
            Tab("Agenda", systemImage: "calendar") {
                AgendaView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .environment(repo)
        .environment(favorites)
        .environment(settings)
    }
}

#Preview {
    RootView()
}
