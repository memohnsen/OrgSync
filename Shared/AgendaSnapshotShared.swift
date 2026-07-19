//
//  AgendaSnapshotShared.swift
//  OrgSync + OrgSyncWidgets
//
//  The single source of truth for the widget payload and app-group storage
//  locations, compiled into BOTH the app and the widget target. It replaces the
//  field-for-field copies the widget used to keep, so a change to the model or a
//  key can't silently desynchronize the two.
//

import Foundation

/// Compact, Codable agenda payload written to the app group and read by widgets.
struct AgendaSnapshot: Codable {
    static let appGroupIdentifier = "group.com.memohnsen.OrgSync"
    static let fileName = "agenda-snapshot.json"
    /// App-group key holding snapshot ids the widget asked to complete but that
    /// the app hasn't yet written into the notes.
    static let pendingCompletionsKey = "widget.pendingCompletions"
    /// App-group key holding the favorite notes' relative paths.
    static let favoritesKey = "favorites.relativePaths"

    var generatedAt: Date
    var items: [AgendaSnapshotItem]
}

struct AgendaSnapshotItem: Codable, Identifiable {
    var id: String
    var title: String
    var filePath: String
    var scheduled: Date?
    var deadline: Date?
    var priority: String?
    var tags: [String]
}
