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
    @State private var onboarding: OnboardingState
    @State private var selectedTab = "notes"
    @State private var openedNotePath: String?
    @State private var isShowingSplash = true

    private let holdsSplashForUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing-hold-splash")

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let repo = RepoStore()
        let settings = SettingsStore()
        _repo = State(initialValue: repo)
        _settings = State(initialValue: settings)
        _sync = State(initialValue: SyncEngine(repo: repo, settings: settings))
        _reminders = State(initialValue: RemindersSyncEngine(settings: settings))
        _onboarding = State(initialValue: OnboardingState())
    }

    var body: some View {
        @Bindable var onboarding = onboarding

        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Notes", systemImage: "note.text", value: "notes") {
                    NotesView(openNotePath: $openedNotePath)
                }
                Tab("Agenda", systemImage: "calendar", value: "agenda") {
                    AgendaView()
                }
                Tab("Settings", systemImage: "gearshape", value: "settings") {
                    SettingsView()
                }
            }

            if isShowingSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .environment(repo)
        .environment(favorites)
        .environment(settings)
        .environment(sync)
        .environment(reminders)
        .environment(onboarding)
        .fullScreenCover(isPresented: $onboarding.isPresented) {
            OnboardingView(
                openInbox: {
                    onboarding.finish()
                    selectedTab = "notes"
                    openedNotePath = "inbox.org"
                },
                connectRepository: {
                    onboarding.finish()
                    selectedTab = "settings"
                }
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .onOpenURL { url in
            // Widgets use orgsync://agenda and orgsync://note/<repo path>.
            // Note links land in the Notes tab; the user can then open the
            // named file in the existing native browser.
            if url.host == "agenda" {
                selectedTab = "agenda"
            } else {
                selectedTab = "notes"
                openedNotePath = url.path.removingPercentEncoding?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }
        .task {
            guard !holdsSplashForUITesting else { return }
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                isShowingSplash = false
            }
        }
        .preferredColorScheme(settings.appearance == "light" ? .light : settings.appearance == "dark" ? .dark : nil)
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        let event: AutoSyncLifecycleEvent
        switch phase {
        case .active: event = .active
        case .background: event = .background
        default: event = .inactive
        }
        for action in AutoSyncPolicy.actions(
            for: event,
            autoSyncEnabled: settings.autoSync,
            isConnected: sync.isConnected,
            pullOnOpen: settings.pullOnOpen,
            pushOnClose: settings.pushOnClose,
            remindersSyncEnabled: settings.remindersSync
        ) {
            switch action {
            case .pull:
                Task { await sync.pullNow(); repo.refresh() }
            case .pullThenSyncReminders:
                Task { await sync.pullNow(); await reminders.sync(repo: repo); repo.refresh() }
            case .syncReminders:
                Task { await reminders.sync(repo: repo) }
            case .push:
                pushInBackground()
            }
        }
    }

    /// Kicks off a commit & push wrapped in a UIKit background task so it has a
    /// chance to finish after the scene backgrounds.
    private func pushInBackground() {
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "OrgSyncPush")
        guard taskID != .invalid else { return }
        Task {
            await sync.pushOnCloseNow()
            await MainActor.run { UIApplication.shared.endBackgroundTask(taskID) }
        }
    }
}

#Preview {
    RootView()
}
