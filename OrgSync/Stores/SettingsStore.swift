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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        repoURL = defaults.string(forKey: Key.repoURL) ?? ""
        branch = defaults.string(forKey: Key.branch) ?? "main"
        autoSync = defaults.bool(forKey: Key.autoSync)
        pullOnOpen = defaults.bool(forKey: Key.pullOnOpen)
        pushOnClose = defaults.bool(forKey: Key.pushOnClose)
        remindersSync = defaults.bool(forKey: Key.remindersSync)
        token = KeychainHelper.get(account: Self.tokenAccount) ?? ""
    }
}
