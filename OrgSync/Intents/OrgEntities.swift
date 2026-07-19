//
//  OrgEntities.swift
//  OrgSync
//
//  App Intent entities so Siri and Shortcuts can refer to specific tasks and
//  notes — pick them from a list, match them by spoken name, and pass them into
//  actions like "complete" or "open".
//

import AppIntents

// MARK: - Task

struct OrgTaskEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static var defaultQuery = OrgTaskQuery()

    var id: String
    var title: String
    var noteName: String
    var dueDescription: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: dueDescription.map { "\($0)" } ?? "\(noteName)"
        )
    }

    init(_ item: OrgTodoItem) {
        id = AgendaSnapshotWriter.snapshotID(for: item)
        title = item.title
        noteName = item.outline.filePath
        dueDescription = ReminderSyncRules.relevantDate(for: item)?
            .formatted(.dateTime.month(.abbreviated).day())
    }
}

struct OrgTaskQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [OrgTaskEntity] {
        let wanted = Set(identifiers)
        return AppServices.openTasks()
            .filter { wanted.contains(AgendaSnapshotWriter.snapshotID(for: $0)) }
            .map(OrgTaskEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [OrgTaskEntity] {
        Array(AppServices.tasks(in: .upcoming).prefix(30)).map(OrgTaskEntity.init)
    }
}

extension OrgTaskQuery: EntityStringQuery {
    @MainActor
    func entities(matching string: String) async throws -> [OrgTaskEntity] {
        AppServices.openTasks()
            .filter { $0.title.localizedCaseInsensitiveContains(string) }
            .map(OrgTaskEntity.init)
    }
}

// Notes are represented by the assistant-schema NoteDocumentEntity in
// OrgAssistantSchemas.swift (the WordProcessor document domain).
