//
//  OrgSyncShortcuts.swift
//  OrgSync
//
//  Registers OrgSync's intents as App Shortcuts so they get Siri phrases and
//  appear in Shortcuts and Spotlight without any user setup.
//

import AppIntents

struct OrgSyncShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Capture a note in \(.applicationName)",
                "New \(.applicationName) task"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodaysTasksIntent(),
            phrases: [
                "What's on my \(.applicationName) agenda today",
                "Show today's \(.applicationName) tasks"
            ],
            shortTitle: "Today's Tasks",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: UpcomingTasksIntent(),
            phrases: [
                "Show upcoming \(.applicationName) tasks",
                "What's coming up in \(.applicationName)"
            ],
            shortTitle: "Upcoming Tasks",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: CreateNoteDocumentIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New \(.applicationName) note"
            ],
            shortTitle: "Create Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete a task in \(.applicationName)",
                "Mark a \(.applicationName) task done"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: SyncNowIntent(),
            phrases: [
                "Sync \(.applicationName)",
                "Sync \(.applicationName) with GitHub"
            ],
            shortTitle: "Sync",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: OpenNoteDocumentIntent(),
            phrases: [
                "Open a note in \(.applicationName)"
            ],
            shortTitle: "Open Note",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: OpenAgendaIntent(),
            phrases: [
                "Open my \(.applicationName) agenda"
            ],
            shortTitle: "Open Agenda",
            systemImageName: "calendar"
        )
    }
}
