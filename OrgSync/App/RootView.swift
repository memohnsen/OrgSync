//
//  RootView.swift
//  OrgSync
//
//  Top-level tab shell: Notes, Agenda, Settings. Owns the app's shared stores
//  and injects them into the environment for the tab content to consume. Also
//  drives the optional auto-sync behaviour off the scene lifecycle: pull when
//  the app becomes active, commit & push when it goes to the background.
//

import SwiftUI
import UIKit

struct RootView: View {
    @State private var repo: RepoStore
    @State private var favorites = FavoritesStore()
    @State private var settings: SettingsStore
    @State private var sync: SyncEngine

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let repo = RepoStore()
        let settings = SettingsStore()
        _repo = State(initialValue: repo)
        _settings = State(initialValue: settings)
        _sync = State(initialValue: SyncEngine(repo: repo, settings: settings))
    }

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
        .environment(sync)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        guard settings.autoSync, sync.isConnected else { return }
        switch phase {
        case .active:
            if settings.pullOnOpen {
                Task { await sync.pullNow(); repo.refresh() }
            }
        case .background:
            if settings.pushOnClose {
                pushInBackground()
            }
        default:
            break
        }
    }

    /// Kicks off a commit & push wrapped in a UIKit background task so it has a
    /// chance to finish after the scene backgrounds.
    private func pushInBackground() {
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "OrgSyncPush")
        guard taskID != .invalid else { return }
        Task {
            await sync.pushNow()
            await MainActor.run { UIApplication.shared.endBackgroundTask(taskID) }
        }
    }
}

#Preview {
    RootView()
}
