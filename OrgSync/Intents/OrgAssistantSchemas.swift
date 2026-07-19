//
//  OrgAssistantSchemas.swift
//  OrgSync
//
//  Apple Intelligence assistant-schema conformances. Org notes are text
//  documents, so they map onto the WordProcessor domain: a document entity plus
//  the create/open document intents. This is what lets the new Siri reason about
//  notes semantically rather than only through app-specific intents. Tasks,
//  agenda, and sync have no matching assistant schema, so they stay as the
//  standard App Intents in OrgSyncIntents.swift.
//

import AppIntents
import Foundation
import UniformTypeIdentifiers

@AppEntity(schema: .wordProcessor.document)
nonisolated struct NoteDocumentEntity {
    static var defaultQuery = NoteDocumentQuery()
    static var supportedContentTypes: [UTType] = [.plainText]

    let id: FileEntityIdentifier
    var name: String
    var creationDate: Date?
    var modificationDate: Date?

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(item: FileItem) throws {
        self.id = try .file(url: item.url)
        self.name = item.displayName
        let values = try? item.url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        self.creationDate = values?.creationDate ?? item.modifiedDate
        self.modificationDate = values?.contentModificationDate ?? item.modifiedDate
    }
}

struct NoteDocumentQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [FileEntityIdentifier]) async throws -> [NoteDocumentEntity] {
        let files = AppServices.repo.allOrgFiles()
        var result: [NoteDocumentEntity] = []
        for identifier in identifiers {
            guard let url = try? await identifier.fileURL,
                  let item = files.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }),
                  let entity = try? NoteDocumentEntity(item: item) else { continue }
            result.append(entity)
        }
        return result
    }

    @MainActor
    func suggestedEntities() async throws -> [NoteDocumentEntity] {
        AppServices.repo.allOrgFiles().prefix(40).compactMap { try? NoteDocumentEntity(item: $0) }
    }
}

extension NoteDocumentQuery: EntityStringQuery {
    @MainActor
    func entities(matching string: String) async throws -> [NoteDocumentEntity] {
        AppServices.repo.allOrgFiles()
            .filter { $0.displayName.localizedCaseInsensitiveContains(string) }
            .compactMap { try? NoteDocumentEntity(item: $0) }
    }
}

// OrgSync notes have no document templates, but the create schema requires a
// template parameter, so we expose an empty template entity.
@AppEntity(schema: .wordProcessor.template)
nonisolated struct NoteTemplateEntity {
    static var defaultQuery = NoteTemplateQuery()

    let id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct NoteTemplateQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [NoteTemplateEntity] { [] }
    func entities(matching string: String) async throws -> [NoteTemplateEntity] { [] }
    func suggestedEntities() async throws -> [NoteTemplateEntity] { [] }
}

@AppIntent(schema: .wordProcessor.create)
nonisolated struct CreateNoteDocumentIntent {
    var name: String?
    var template: NoteTemplateEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NoteDocumentEntity> {
        let requested = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteName = (requested?.isEmpty == false ? requested! : "Untitled")
        guard let file = AppServices.repo.createNote(named: noteName, in: AppServices.repo.repoURL) else {
            throw OrgIntentError.noteCreateFailed
        }
        return .result(value: try NoteDocumentEntity(item: file))
    }
}

@AppIntent(schema: .wordProcessor.open)
nonisolated struct OpenNoteDocumentIntent {
    static var openAppWhenRun = true

    var target: NoteDocumentEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = try? await target.id.fileURL,
           let item = AppServices.repo.allOrgFiles().first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            AppServices.requestOpen(tab: "notes", note: item.relativePath)
        }
        return .result()
    }
}
