//
//  TaskCompletionService.swift
//  OrgSync
//
//  One completion path for the app, widgets, intents, agenda, and Reminders.
//  It keeps repeaters active and optionally archives one-off inbox tasks.
//

import Foundation

@MainActor
enum TaskCompletionService {
    @discardableResult
    static func complete(_ item: OrgTodoItem, repo: RepoStore, settings: SettingsStore) -> Bool {
        guard let sourceFile = repo.item(forRelativePath: item.outline.filePath) else { return false }
        var source = repo.document(of: sourceFile)
        let original = source

        // Marks the task DONE where it lives (advancing a repeater's timestamp
        // back to its first active state when present).
        func completeInPlace() -> Bool {
            guard source.mutateHeadline(at: item.outline, {
                ReminderSyncRules.complete(&$0, item: item, document: original)
            }) else { return false }
            return repo.write(source.serialize(), to: sourceFile)
        }

        // A repeating task must remain in its source document.
        if item.scheduled?.repeater != nil || item.deadline?.repeater != nil {
            return completeInPlace()
        }

        guard settings.archiveCompletedInboxTasks,
              item.outline.filePath.caseInsensitiveCompare("inbox.org") == .orderedSame else {
            return completeInPlace()
        }

        guard var completed = source.removeHeadline(at: item.outline) else { return false }
        ReminderSyncRules.complete(&completed, item: item, document: original)
        let doneFile = repo.item(forRelativePath: "done.org")
            ?? repo.createNote(named: "done", in: repo.repoURL)
        guard let doneFile else { return false }
        var done = repo.document(of: doneFile)
        done.headlines.append(completed)

        // Write the destination before removing the inbox source, preferring a
        // recoverable duplicate over losing a completed task on a disk error.
        var success = false
        repo.performMutationBatch {
            success = repo.write(done.serialize(), to: doneFile)
                && repo.write(source.serialize(), to: sourceFile)
        }
        return success
    }
}
