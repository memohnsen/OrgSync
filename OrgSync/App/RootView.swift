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
    @State private var reminders: RemindersSyncEngine
    @State private var selectedTab = "notes"

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let repo = RepoStore()
        let settings = SettingsStore()
        _repo = State(initialValue: repo)
        _settings = State(initialValue: settings)
        _sync = State(initialValue: SyncEngine(repo: repo, settings: settings))
        _reminders = State(initialValue: RemindersSyncEngine(settings: settings))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Notes", systemImage: "note.text", value: "notes") {
                NotesView()
            }
            Tab("Agenda", systemImage: "calendar", value: "agenda") {
                AgendaView()
            }
            Tab("Settings", systemImage: "gearshape", value: "settings") {
                SettingsView()
            }
        }
        .environment(repo)
        .environment(favorites)
        .environment(settings)
        .environment(sync)
        .environment(reminders)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .onOpenURL { url in
            // Widgets use orgsync://agenda and orgsync://note/<repo path>.
            // Note links land in the Notes tab; the user can then open the
            // named file in the existing native browser.
            selectedTab = url.host == "agenda" ? "agenda" : "notes"
        }
        .preferredColorScheme(settings.appearance == "light" ? .light : settings.appearance == "dark" ? .dark : nil)
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        guard settings.autoSync, sync.isConnected else { return }
        switch phase {
        case .active:
            if settings.pullOnOpen {
                Task { await sync.pullNow(); await reminders.sync(repo: repo); repo.refresh() }
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
