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
        static let autoSync = "settings.sync.autoSync"
        static let pullOnOpen = "settings.sync.pullOnOpen"
        static let pushOnClose = "settings.sync.pushOnClose"
        static let remindersSync = "settings.reminders.sync"
        static let remindersListID = "settings.reminders.listID"
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

    var autoSync: Bool {
        didSet { defaults.set(autoSync, forKey: Key.autoSync) }
    }

    var pullOnOpen: Bool {
        didSet { defaults.set(pullOnOpen, forKey: Key.pullOnOpen) }
    }

    var pushOnClose: Bool {
        didSet { defaults.set(pushOnClose, forKey: Key.pushOnClose) }
    }

    // MARK: - Reminders

    var remindersSync: Bool {
        didSet { defaults.set(remindersSync, forKey: Key.remindersSync) }
    }

    var remindersListID: String {
        didSet { defaults.set(remindersListID, forKey: Key.remindersListID) }
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
        autoSync = defaults.bool(forKey: Key.autoSync)
        pullOnOpen = defaults.bool(forKey: Key.pullOnOpen)
        pushOnClose = defaults.bool(forKey: Key.pushOnClose)
        remindersSync = defaults.bool(forKey: Key.remindersSync)
        remindersListID = defaults.string(forKey: Key.remindersListID) ?? ""
        agendaDays = max(1, defaults.object(forKey: Key.agendaDays) as? Int ?? 7)
        appearance = defaults.string(forKey: Key.appearance) ?? "system"
        let storedKeywords = defaults.string(forKey: Key.todoKeywords)
        // Earlier builds accidentally classified PROGRESS and WAITING as
        // completed. Repair that exact legacy default without touching a
        // person's intentionally customized workflow.
        todoKeywords = storedKeywords == "TODO | PROGRESS WAITING DONE"
            ? OrgTodoConfig.defaultPreference
            : storedKeywords ?? OrgTodoConfig.defaultPreference
        todoStatusColors = defaults.dictionary(forKey: Key.todoStatusColors) as? [String: String] ?? [:]
        token = KeychainHelper.get(account: Self.tokenAccount) ?? ""
    }
}
