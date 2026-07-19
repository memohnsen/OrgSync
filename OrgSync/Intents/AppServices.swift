//
//  AppServices.swift
//  OrgSync
//
//  Shared main-actor entry point for App Intents (Siri, Shortcuts, Spotlight).
//  When the app is running, RootView registers its live stores so intent
//  mutations flow straight into the UI; when Siri runs an intent while the app
//  is backgrounded, transient stores are created on demand so the action still
//  works headlessly. Intents live in the app target (not an extension) because
//  the notes are in the app's Documents sandbox, which only in-app code reaches.
//

import Foundation

extension Notification.Name {
    /// Posted by an intent that wants the running app to navigate somewhere.
    static let orgSyncOpenRequest = Notification.Name("orgsync.openRequest")
}

@MainActor
enum AppServices {
    enum TaskRange { case today, week, upcoming }

    // MARK: Store access

    private static var registeredRepo: RepoStore?
    private static var registeredSettings: SettingsStore?
    private static var registeredSync: SyncEngine?

    static func register(repo: RepoStore, settings: SettingsStore, sync: SyncEngine) {
        registeredRepo = repo
        registeredSettings = settings
        registeredSync = sync
    }

    static var settings: SettingsStore {
        if let registeredSettings { return registeredSettings }
        let store = SettingsStore(); registeredSettings = store; return store
    }
    static var repo: RepoStore {
        if let registeredRepo { return registeredRepo }
        let store = RepoStore(); registeredRepo = store; return store
    }
    static var sync: SyncEngine {
        if let registeredSync { return registeredSync }
        let engine = SyncEngine(repo: repo, settings: settings); registeredSync = engine; return engine
    }

    // MARK: Task queries

    static func openTasks() -> [OrgTodoItem] {
        repo.allTodoItems().filter { !$0.isDone }
    }

    /// Open, dated tasks inside a window, earliest first (overdue included).
    static func tasks(in range: TaskRange) -> [OrgTodoItem] {
        let calendar = Calendar.current
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: .now)) ?? .now
        return openTasks().compactMap { item -> (item: OrgTodoItem, date: Date)? in
            guard let date = ReminderSyncRules.relevantDate(for: item) else { return nil }
            return (item, date)
        }.filter { entry in
            switch range {
            case .today: entry.date < startOfTomorrow
            case .week: entry.date < endOfWeek
            case .upcoming: true
            }
        }.sorted { $0.date < $1.date }.map(\.item)
    }

    static func task(id: String) -> OrgTodoItem? {
        openTasks().first { AgendaSnapshotWriter.snapshotID(for: $0) == id }
    }

    // MARK: Mutations

    /// Marks the task DONE in its note. `repo.write` refreshes the widget
    /// snapshot, so all widgets update too.
    @discardableResult
    static func completeTask(id: String) -> Bool {
        guard let item = task(id: id) else { return false }
        return TaskCompletionService.complete(item, repo: repo, settings: settings)
    }

    /// Appends a new TODO to inbox.org, optionally scheduled for a day.
    @discardableResult
    static func capture(_ text: String, scheduled: Date?) -> Bool {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let file = repo.item(forRelativePath: "inbox.org") ?? repo.createNote(named: "inbox", in: repo.repoURL)
        guard let file else { return false }
        var body = repo.text(of: file)
        if !body.isEmpty && !body.hasSuffix("\n") { body += "\n" }
        body += "\n* TODO \(title)\n"
        if let scheduled {
            body += "SCHEDULED: \(OrgTimestamp(date: scheduled, isActive: true, includeTime: false).serialize())\n"
        }
        return repo.write(body, to: file)
    }

    // MARK: Navigation

    private(set) static var pendingOpenTab: String?
    private(set) static var pendingOpenNote: String?

    static func requestOpen(tab: String, note: String?) {
        pendingOpenTab = tab
        pendingOpenNote = note
        NotificationCenter.default.post(name: .orgSyncOpenRequest, object: nil)
    }

    static func consumePendingOpen() -> (tab: String?, note: String?) {
        defer { pendingOpenTab = nil; pendingOpenNote = nil }
        return (pendingOpenTab, pendingOpenNote)
    }
}
