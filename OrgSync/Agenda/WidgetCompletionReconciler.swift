//
//  WidgetCompletionReconciler.swift
//  OrgSync
//
//  Applies TODO completions requested from the widget. The widget extension is
//  sandboxed out of the notes in the app's Documents directory, so its complete
//  button only records an item's snapshot id into the shared app group. The app
//  marks the real headline DONE here the next time it runs, then rewrites the
//  widget snapshot so every widget reflects the persisted state.
//

import Foundation

@MainActor
enum WidgetCompletionReconciler {
    /// Drains the widget completion queue and marks the matching headlines DONE.
    /// Idempotent: safe to call on every foreground.
    static func reconcile(repo: RepoStore, settings providedSettings: SettingsStore? = nil, defaults: UserDefaults? = nil) {
        let settings = providedSettings ?? SettingsStore()
        let defaults = defaults ?? UserDefaults(suiteName: AgendaSnapshot.appGroupIdentifier) ?? .standard
        let pending = defaults.stringArray(forKey: AgendaSnapshot.pendingCompletionsKey) ?? []
        guard !pending.isEmpty else { return }
        defaults.removeObject(forKey: AgendaSnapshot.pendingCompletionsKey)

        let wanted = Set(pending)
        let matches = repo.allTodoItems().filter {
            wanted.contains(AgendaSnapshotWriter.snapshotID(for: $0))
                && !OrgTodoStatusPalette.isCompleted($0.keyword)
                // Calendar-mirror entries are read-only events; a DONE written
                // there would just be regenerated away on the next sync.
                && $0.outline.filePath != CalendarSyncRules.fileName
        }
        guard !matches.isEmpty else { return }

        var didWrite = false
        for item in matches {
            if TaskCompletionService.complete(item, repo: repo, settings: settings) { didWrite = true }
        }

        if didWrite {
            repo.refresh()
            AgendaSnapshotWriter.write(repo: repo)
        }
    }
}
