//
//  AgendaSnapshot.swift
//  OrgSync
//
//  Compact, Codable agenda data shared with the WidgetKit extension in Phase 6.
//

import Foundation
import WidgetKit

struct AgendaSnapshot: Codable {
    static let appGroupIdentifier = "group.com.memohnsen.OrgSync"
    static let fileName = "agenda-snapshot.json"

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

enum AgendaSnapshotWriter {
    /// Regenerates the widget payload from the authoritative local mirror.
    /// Keeping this here ensures widgets refresh after any note edit, pull,
    /// merge, Agenda action, or Reminders reconciliation—not only after the
    /// Agenda screen happens to be opened.
    static func write(repo: RepoStore) {
        write(repo.allTodoItems().filter { !OrgTodoStatusPalette.isCompleted($0.keyword) })
    }

    static func write(_ items: [OrgTodoItem]) {
        let snapshot = AgendaSnapshot(generatedAt: .now, items: items.map { item in
            AgendaSnapshotItem(
                id: item.outline.filePath + "|" + item.outline.headingPath.joined(separator: "/") + "|" + String(item.outline.index),
                title: item.title,
                filePath: item.outline.filePath,
                scheduled: item.scheduled?.date(),
                deadline: item.deadline?.date(),
                priority: item.priority.map(String.init),
                tags: item.tags
            )
        })
        guard let data = try? JSONEncoder.agenda.encode(snapshot) else { return }
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AgendaSnapshot.appGroupIdentifier
        ) else { return }
        try? data.write(to: directory.appendingPathComponent(AgendaSnapshot.fileName), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private extension JSONEncoder {
    static let agenda: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
