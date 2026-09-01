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
    @State private var notifications = TodoNotificationScheduler()
    @State private var subscriptions = SubscriptionStore()
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
        .modifier(appEnvironment)
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
            // Refresh the pending notification set on launch: fire dates in the
            // past are dropped and note edits made outside the app are picked up.
            await notifications.reschedule(repo: repo, settings: settings, isProUnlocked: subscriptions.isUnlocked)
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
        // Haptics for sync outcomes: a light success tap when a sync/pull/push
        // completes, an error buzz when one fails.
        .sensoryFeedback(.success, trigger: sync.lastSyncDate) { old, new in old != nil && new != nil }
        .sensoryFeedback(.error, trigger: sync.lastError) { _, new in new != nil }
        .preferredColorScheme(settings.appearance == "light" ? .light : settings.appearance == "dark" ? .dark : nil)
    }

    /// Store injection plus the cross-cutting behaviors (notification
    /// rescheduling, post-onboarding paywall), bundled outside `body` to keep
    /// that expression within the type-checker's budget.
    private var appEnvironment: some ViewModifier {
        AppEnvironmentModifier(
            repo: repo, favorites: favorites, settings: settings, sync: sync,
            reminders: reminders, calendar: calendar, onboarding: onboarding,
            notifications: notifications, subscriptions: subscriptions)
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

/// Injects every shared store and attaches the cross-cutting app behaviors.
private struct AppEnvironmentModifier: ViewModifier {
    let repo: RepoStore
    let favorites: FavoritesStore
    let settings: SettingsStore
    let sync: SyncEngine
    let reminders: RemindersSyncEngine
    let calendar: CalendarSyncEngine
    let onboarding: OnboardingState
    let notifications: TodoNotificationScheduler
    let subscriptions: SubscriptionStore

    func body(content: Content) -> some View {
        content
            // Presentation modifiers must sit INSIDE the .environment calls:
            // a sheet's content inherits the environment visible at its
            // attachment point, so attaching it above the injections crashed
            // ProPaywallSheet's @Environment(SubscriptionStore.self) lookup.
            .modifier(TodoNotificationRescheduling(repo: repo, settings: settings, scheduler: notifications, subscriptions: subscriptions))
            .modifier(PostOnboardingPaywall(onboarding: onboarding, subscriptions: subscriptions))
            .environment(repo)
            .environment(favorites)
            .environment(settings)
            .environment(sync)
            .environment(reminders)
            .environment(calendar)
            .environment(onboarding)
            .environment(notifications)
            .environment(subscriptions)
    }
}

/// Rebuilds the pending local-notification set whenever a note changes or a
/// notification preference changes. Lives outside RootView.body to keep that
/// expression within the type-checker's budget.
private struct TodoNotificationRescheduling: ViewModifier {
    let repo: RepoStore
    let settings: SettingsStore
    let scheduler: TodoNotificationScheduler
    let subscriptions: SubscriptionStore

    /// One equatable fingerprint of every input the plan depends on, so a
    /// single onChange covers note edits, the notification settings, and the
    /// Pro entitlement (notifications are a Pro feature).
    private var fingerprint: String {
        "\(repo.revision)|\(settings.todoNotifications)|\(settings.allDayNotificationMinutes ?? -1)|\(settings.timedNotificationOffsets)|\(subscriptions.isUnlocked)"
    }

    func body(content: Content) -> some View {
        content.onChange(of: fingerprint) { _, _ in
            Task { await scheduler.reschedule(repo: repo, settings: settings, isProUnlocked: subscriptions.isUnlocked) }
        }
    }
}

#Preview {
    RootView()
}
