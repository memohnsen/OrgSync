//
//  RootView.swift
//  OrgSync
//
//  Top-level tab shell: Notes, Agenda, Settings. Owns the app's shared stores
//  and injects them into the environment for the tab content to consume. Also
//  drives the optional auto-sync behaviour off the scene lifecycle: pull when
//  the app becomes active.
//

import SwiftUI

struct RootView: View {
    @State private var repo: RepoStore
    @State private var favorites = FavoritesStore()
    @State private var settings: SettingsStore
    @State private var sync: SyncEngine
    @State private var reminders: RemindersSyncEngine
    @State private var calendar: CalendarSyncEngine
    @State private var onboarding: OnboardingState
    @State private var selectedTab = "notes"
    @State private var openedNotePath: String?
    @State private var isShowingAgendaQuickAdd = false
    @State private var isShowingSplash = true
    @State private var isShowingSyncError = false

    private let holdsSplashForUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing-hold-splash")

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let repo = RepoStore()
        let settings = SettingsStore()
        _repo = State(initialValue: repo)
        _settings = State(initialValue: settings)
        _sync = State(initialValue: SyncEngine(repo: repo, settings: settings))
        _reminders = State(initialValue: RemindersSyncEngine(settings: settings))
        _calendar = State(initialValue: CalendarSyncEngine(settings: settings))
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
                    AgendaView(showQuickAdd: $isShowingAgendaQuickAdd)
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
        .environment(calendar)
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
        .onReceive(NotificationCenter.default.publisher(for: .orgSyncOpenRequest)) { _ in
            let target = AppServices.consumePendingOpen()
            if let tab = target.tab { selectedTab = tab }
            if let note = target.note { openedNotePath = note }
        }
        .onOpenURL { url in
            // Widgets use orgsync://agenda (optionally with ?newTask=1) and
            // orgsync://note/<repo path>.
            // Note links land in the Notes tab; the user can then open the
            // named file in the existing native browser.
            if url.host == "agenda" {
                selectedTab = "agenda"
                isShowingAgendaQuickAdd = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.contains(where: { $0.name == "newTask" && $0.value == "1" }) == true
            } else {
                selectedTab = "notes"
                openedNotePath = url.path.removingPercentEncoding?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }
        .task {
            // Share the live stores with App Intents so Siri/Shortcuts mutations
            // flow straight into the running UI.
            AppServices.register(repo: repo, settings: settings, sync: sync, reminders: reminders, calendar: calendar)
            // An open intent that launched the app may have posted its request
            // before this view subscribed; apply any pending target now.
            let target = AppServices.consumePendingOpen()
            if let tab = target.tab { selectedTab = tab }
            if let note = target.note { openedNotePath = note }
            // Initial launch doesn't always fire the scenePhase change, so drain
            // the widget completion queue here too. Idempotent.
            WidgetCompletionReconciler.reconcile(repo: repo)
            guard !holdsSplashForUITesting else { return }
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                isShowingSplash = false
            }
            // An error left over from a previous session (e.g. a failed
            // push-on-close) is already set, so onChange never fires for it.
            if sync.lastError != nil { isShowingSyncError = true }
        }
        // One app-level presenter for sync failures, so an error surfaces no
        // matter which tab is frontmost — including failures from auto-pushes
        // that happened while the app was closing and are only seen on the
        // next foreground. The toolbar badge persists until dismissed here.
        .onChange(of: sync.lastError) { _, newValue in
            isShowingSyncError = newValue != nil && !isShowingSplash
        }
        .alert("Sync Failed", isPresented: $isShowingSyncError) {
            Button("OK", role: .cancel) { sync.lastError = nil }
        } message: {
            Text(sync.lastError ?? "")
        }
        .preferredColorScheme(settings.appearance == "light" ? .light : settings.appearance == "dark" ? .dark : nil)
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        let event: AutoSyncLifecycleEvent
        switch phase {
        case .active: event = .active
        case .background:
            BackgroundRefresh.schedule()
            return
        default: event = .inactive
        }
        // Apply any TODO completions tapped in the widget before syncing, so the
        // marked-done note is included in the outgoing push. Refresh the
        // read-only calendar mirror on every open as well.
        if phase == .active {
            WidgetCompletionReconciler.reconcile(repo: repo)
            if settings.calendarSync {
                Task { await calendar.sync(repo: repo) }
            }
        }
        for action in AutoSyncPolicy.actions(
            for: event,
            isConnected: sync.isConnected,
            pullOnOpen: settings.pullOnOpen,
            remindersSyncEnabled: settings.remindersSync
        ) {
            switch action {
            case .pull:
                Task { await sync.pullNow(); repo.refresh() }
            case .pullThenSyncReminders:
                Task { await sync.pullNow(); await reminders.sync(repo: repo); repo.refresh() }
            case .syncReminders:
                Task { await reminders.sync(repo: repo) }
            }
        }
    }
}

#Preview {
    RootView()
}
