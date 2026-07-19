//
//  SettingsStore.swift
//  OrgSync
//
//  Persists user-facing configuration (GitHub connection details and sync
//  preferences). Plain values live in UserDefaults; the Personal Access Token
//  is stored in the Keychain via `KeychainHelper` and never written to
//  UserDefaults. Nothing here performs network calls yet — Phase 4 wires these
//  values into the sync engine.
//

import Foundation
import Observation

@Observable
final class SettingsStore {
    /// Keychain account key under which the GitHub PAT is stored.
    static let tokenAccount = "github.pat"

    private enum Key {
        static let repoURL = "settings.github.repoURL"
        static let branch = "settings.github.branch"
        static let pullOnOpen = "settings.sync.pullOnOpen"
        static let remindersSync = "settings.reminders.sync"
        static let remindersListID = "settings.reminders.listID"
        static let calendarSync = "settings.calendar.sync"
        static let calendarShowInAgenda = "settings.calendar.showInAgenda"
        static let archiveCompletedInboxTasks = "settings.inbox.archiveCompletedTasks"
        static let agendaDays = "settings.agenda.days"
        static let appearance = "settings.appearance"
        static let todoKeywords = "settings.todo.keywords"
        static let todoStatusColors = "settings.todo.statusColors"
    }

    private let defaults: UserDefaults

    // MARK: - GitHub

    var repoURL: String {
        didSet { defaults.set(repoURL, forKey: Key.repoURL) }
    }

    var branch: String {
        didSet { defaults.set(branch, forKey: Key.branch) }
    }

    /// The GitHub Personal Access Token, backed by the Keychain.
    var token: String {
        didSet {
            guard token != oldValue else { return }
            KeychainHelper.set(token, account: Self.tokenAccount)
        }
    }

    // MARK: - Sync preferences

    var pullOnOpen: Bool {
        didSet { defaults.set(pullOnOpen, forKey: Key.pullOnOpen) }
    }


    // MARK: - Reminders

    var remindersSync: Bool {
        didSet { defaults.set(remindersSync, forKey: Key.remindersSync) }
    }

    var remindersListID: String {
        didSet { defaults.set(remindersListID, forKey: Key.remindersListID) }
    }

    // MARK: - Calendar

    /// Mirrors upcoming calendar events into the read-only calendar.org file.
    var calendarSync: Bool {
        didSet { defaults.set(calendarSync, forKey: Key.calendarSync) }
    }

    /// Whether mirrored calendar events appear in the Agenda tab and widgets.
    var calendarShowInAgenda: Bool {
        didSet { defaults.set(calendarShowInAgenda, forKey: Key.calendarShowInAgenda) }
    }

    /// UserDefaults key for `calendarShowInAgenda`, read directly by
    /// AgendaSnapshotWriter (widget payload generation happens outside the
    /// store graph, mirroring how RepoStore reads the TODO keywords).
    static var calendarShowInAgendaKey: String { Key.calendarShowInAgenda }
    /// When enabled, completed one-off tasks in `inbox.org` are moved to
    /// `done.org`. Repeating tasks always stay in place so they can recur.
    var archiveCompletedInboxTasks: Bool {
        didSet { defaults.set(archiveCompletedInboxTasks, forKey: Key.archiveCompletedInboxTasks) }
    }
    var agendaDays: Int { didSet { defaults.set(agendaDays, forKey: Key.agendaDays) } }
    var appearance: String { didSet { defaults.set(appearance, forKey: Key.appearance) } }
    var todoKeywords: String { didSet { defaults.set(todoKeywords, forKey: Key.todoKeywords) } }
    var todoStatusColors: [String: String] {
        didSet { defaults.set(todoStatusColors, forKey: Key.todoStatusColors) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        repoURL = defaults.string(forKey: Key.repoURL) ?? ""
        branch = defaults.string(forKey: Key.branch) ?? "main"
        pullOnOpen = defaults.bool(forKey: Key.pullOnOpen)
        remindersSync = defaults.bool(forKey: Key.remindersSync)
        remindersListID = defaults.string(forKey: Key.remindersListID) ?? ""
        calendarSync = defaults.bool(forKey: Key.calendarSync)
        calendarShowInAgenda = defaults.object(forKey: Key.calendarShowInAgenda) as? Bool ?? true
        archiveCompletedInboxTasks = defaults.bool(forKey: Key.archiveCompletedInboxTasks)
        agendaDays = max(1, defaults.object(forKey: Key.agendaDays) as? Int ?? 7)
        appearance = defaults.string(forKey: Key.appearance) ?? "system"
        let storedKeywords = defaults.string(forKey: Key.todoKeywords)
        // Normalize imported and earlier app configurations so only the
        // literal DONE status is completed; every other status stays active.
        todoKeywords = storedKeywords.map {
            OrgTodoStatusConfiguration.preference(
                from: OrgTodoStatusConfiguration.statuses(from: $0)
            )
        } ?? OrgTodoConfig.defaultPreference
        todoStatusColors = defaults.dictionary(forKey: Key.todoStatusColors) as? [String: String] ?? [:]
        token = KeychainHelper.get(account: Self.tokenAccount) ?? ""
    }
}
