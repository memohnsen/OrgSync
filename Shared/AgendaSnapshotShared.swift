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

/// The single definition of agenda date windows, used by every surface — the
/// Agenda tab, the Siri intents, and the widget — so "today" and "this week"
/// can never drift apart between them. What varies per surface (which date a
/// task contributes, whether overdue items belong in an upcoming window) is an
/// explicit choice at the call site, not a re-implementation.
enum AgendaDateWindow: Sendable {
    /// Today plus anything overdue.
    case todayAndOverdue
    /// From today's midnight through `days` days out. `includesOverdue` pulls
    /// overdue items in (Siri, widget); the Agenda tab's Upcoming scope
    /// excludes them because it shows overdue under Today instead.
    case upcoming(days: Int, includesOverdue: Bool)
    /// No bounds.
    case all

    func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .todayAndOverdue:
            guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return false }
            return date < startOfTomorrow
        case let .upcoming(days, includesOverdue):
            guard let end = calendar.date(byAdding: .day, value: days, to: startOfToday) else { return false }
            return date < end && (includesOverdue || date >= startOfToday)
        case .all:
            return true
        }
    }
}
