//
//  FavoritesStore.swift
//  OrgSync
//
//  Persists the set of favorited notes (by repo-relative path). Storage is
//  isolated behind this type so the backing store can be migrated from
//  UserDefaults to the shared App Group container later without touching call
//  sites.
//

import Foundation
import Observation

@Observable
final class FavoritesStore {
    private static let storageKey = "favorites.relativePaths"

    /// Injection point for the backing store. Swap for an App Group
    /// `UserDefaults(suiteName:)` in a later phase.
    private let defaults: UserDefaults

    private(set) var favorites: Set<String>

    init(defaults: UserDefaults? = nil) {
        let shared = UserDefaults(suiteName: AgendaSnapshot.appGroupIdentifier)
        self.defaults = defaults ?? shared ?? .standard
        // Keep favorites created before the App Group entitlement was added.
        let stored = self.defaults.stringArray(forKey: Self.storageKey)
            ?? UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        self.favorites = Set(stored)
        if shared != nil { self.defaults.set(Array(favorites), forKey: Self.storageKey) }
    }

    func isFavorite(_ item: FileItem) -> Bool {
        favorites.contains(item.relativePath)
    }

    func isFavorite(relativePath: String) -> Bool {
        favorites.contains(relativePath)
    }

    func toggle(_ item: FileItem) {
        if favorites.contains(item.relativePath) {
            favorites.remove(item.relativePath)
        } else {
            favorites.insert(item.relativePath)
        }
        persist()
    }

    /// Keeps favorites in sync when a file is renamed/moved.
    func updatePath(from oldPath: String, to newPath: String) {
        guard favorites.contains(oldPath) else { return }
        favorites.remove(oldPath)
        favorites.insert(newPath)
        persist()
    }

    /// Drops a favorite (and any nested favorites, for a deleted folder).
    func remove(pathOrPrefix path: String) {
        let before = favorites.count
        favorites = favorites.filter { $0 != path && !$0.hasPrefix(path + "/") }
        if favorites.count != before {
            persist()
        }
    }

    private func persist() {
        defaults.set(Array(favorites), forKey: Self.storageKey)
    }
}
