//
//  OrgSyncIntents.swift
//  OrgSync
//
//  The App Intents that expose OrgSync to Siri, Shortcuts, and Spotlight:
//  capture a task, complete a task, read today's / upcoming tasks, sync with
//  GitHub, and open a note or the agenda.
//

import AppIntents

enum OrgIntentError: Error, CustomLocalizedStringResourceConvertible {
    case captureFailed
    case taskNotFound
    case notConnected
    case noteCreateFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .captureFailed: "Couldn't save the task to your inbox."
        case .taskNotFound: "That task couldn't be found."
        case .notConnected: "Connect a GitHub repository in Settings first."
        case .noteCreateFailed: "Couldn't create that note. A note with that name may already exist."
        }
    }
}

// MARK: - Capture

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Add a TODO to your OrgSync inbox.")

    @Parameter(title: "Task") var text: String
    @Parameter(title: "Schedule Date") var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to OrgSync")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AppServices.capture(text, scheduled: date) else { throw OrgIntentError.captureFailed }
        return .result(dialog: "Added “\(text)” to your inbox.")
    }
}

// Note creation and opening are handled by the assistant-schema intents in
// OrgAssistantSchemas.swift (CreateNoteDocumentIntent / OpenNoteDocumentIntent).

// MARK: - Complete

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Mark an OrgSync task as done.")

    @Parameter(title: "Task") var task: OrgTaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AppServices.completeTask(id: task.id) else { throw OrgIntentError.taskNotFound }
        return .result(dialog: "Completed “\(task.title)”.")
    }
}

// MARK: - Read

struct TodaysTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Today's Tasks"
    static var description = IntentDescription("List the OrgSync tasks scheduled or due today.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[OrgTaskEntity]> & ProvidesDialog {
        let tasks = AppServices.tasks(in: .today).map(OrgTaskEntity.init)
        return .result(value: tasks, dialog: Self.dialog(for: tasks, scope: String(localized: "today")))
    }

    static func dialog(for tasks: [OrgTaskEntity], scope: String) -> IntentDialog {
        switch tasks.count {
        case 0: "You have nothing due \(scope)."
        case 1: "You have one task \(scope): \(tasks[0].title)."
        default: "You have \(tasks.count) tasks \(scope)."
        }
    }
}

struct UpcomingTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Upcoming Tasks"
    static var description = IntentDescription("List OrgSync tasks scheduled or due in the next week.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[OrgTaskEntity]> & ProvidesDialog {
        let tasks = AppServices.tasks(in: .week).map(OrgTaskEntity.init)
        return .result(value: tasks, dialog: TodaysTasksIntent.dialog(for: tasks, scope: String(localized: "this week")))
    }
}

// MARK: - Sync

struct SyncNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync with GitHub"
    static var description = IntentDescription("Pull remote changes and push local edits.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AppServices.sync.isConnected else { throw OrgIntentError.notConnected }
        await AppServices.sync.syncNow()
        if let error = AppServices.sync.lastError {
            return .result(dialog: "Sync failed: \(error)")
        }
        return .result(dialog: "Synced with GitHub.")
    }
}

// MARK: - Open

struct OpenAgendaIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Agenda"
    static var description = IntentDescription("Open the OrgSync agenda.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.requestOpen(tab: "agenda", note: nil)
        return .result()
    }
}
