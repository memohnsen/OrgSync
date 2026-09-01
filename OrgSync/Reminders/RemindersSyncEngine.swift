//
//  RemindersSyncEngine.swift
//  OrgSync
//
//  EventKit bridge for scheduled/deadline org TODOs. The App Group mapping is
//  intentionally small: a stable org outline key maps to an EKReminder ID.
//

import EventKit
import Foundation
import Observation

@MainActor @Observable
final class RemindersSyncEngine {
    enum Access: Equatable { case unknown, denied, granted }

    private let store = EKEventStore()
    private let settings: SettingsStore
    private let defaults: UserDefaults
    private let mappingKey = "reminders.orgOutlineToIdentifier"

    private(set) var access: Access = .unknown
    private(set) var lists: [EKCalendar] = []
    private(set) var lastError: String?
    private(set) var isSyncing = false

    init(settings: SettingsStore) {
        self.settings = settings
        self.defaults = UserDefaults(suiteName: AgendaSnapshot.appGroupIdentifier) ?? .standard
        refreshAccess()
    }

    func refreshAccess() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        access = status == .fullAccess ? .granted : status == .denied ? .denied : .unknown
        if access == .granted { lists = store.calendars(for: .reminder) }
    }

    func clearError() { lastError = nil }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            refreshAccess()
            if !granted { lastError = "Reminders access was not granted." }
        } catch { lastError = error.localizedDescription; refreshAccess() }
    }

    func sync(repo: RepoStore) async {
        guard settings.remindersSync else { return }
        guard access == .granted else { lastError = "Allow Reminders access in Settings first."; return }
        // Reentrancy guard: overlapping runs (scene-phase sync racing quick-add
        // or background refresh) would read the same mapping snapshot, create
        // duplicate inbox TODOs, and clobber each other's saved mappings.
        guard !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }
        do {
            let list = try orgSyncList()
            var mappings = loadMappings()
            ensurePersistentIDs(repo: repo)
            // The read-only calendar mirror never syncs with Reminders: its
            // entries are events, and the file is regenerated wholesale.
            let inboundItems = repo.allTodoItems().filter { $0.outline.filePath != CalendarSyncRules.fileName }
            // Duplicate keys are possible (a duplicated file or copy-pasted
            // subtree carries its :ID: along) — keep the first occurrence
            // rather than trapping.
            var byKey = Dictionary(inboundItems.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
            // Migrate title-path keys written by older releases.
            for item in inboundItems where item.persistentID != nil {
                let stable = key(item)
                let legacy = legacyKey(item.outline)
                if mappings[stable] == nil, let reminder = mappings.removeValue(forKey: legacy) {
                    mappings[stable] = reminder
                }
                byKey[legacy] = item
            }

            // Reminders -> Org comes first. Otherwise outbound writes would
            // overwrite a completion or due-date edit before we could observe it.
            let predicate = store.predicateForReminders(in: [list])
            for reminder in await fetchReminders(predicate) {
                let reminderID = reminder.calendarItemIdentifier
                guard let mapKey = mappings.first(where: { $0.value == reminderID })?.key else {
                    // Truly unmapped: a reminder created directly in the
                    // dedicated list becomes a TODO in the local inbox.
                    if !reminder.isCompleted, let outline = createInboxTodo(from: reminder, repo: repo) {
                        if let item = repo.allTodoItems().first(where: { $0.outline == outline }) {
                            mappings[key(item)] = reminderID
                        }
                    }
                    continue
                }
                guard var item = byKey[mapKey] else {
                    // The mapped org TODO no longer exists (deleted note or
                    // subtree). Prune the pair instead of treating the reminder
                    // as new, which would resurrect the deleted TODO every sync.
                    mappings.removeValue(forKey: mapKey)
                    try? store.remove(reminder, commit: false)
                    continue
                }
                if let repeater = ReminderSyncRules.repeater(from: reminder),
                   ReminderSyncRules.shouldApplyIncomingRepeater(repeater, to: item) {
                    mutate(item, repo: repo) { headline, _ in
                        ReminderSyncRules.applyIncomingRepeater(repeater, to: &headline)
                    }
                    if let refreshed = repo.allTodoItems().first(where: { key($0) == mapKey }) {
                        item = refreshed
                    }
                }
                if reminder.isCompleted && !item.isDone {
                    _ = TaskCompletionService.complete(item, repo: repo, settings: settings)
                    if let refreshed = repo.allTodoItems().first(where: { key($0) == mapKey }) {
                        item = refreshed
                    }
                }
                if let due = reminder.dueDateComponents, let date = Calendar.current.date(from: due),
                   ReminderSyncRules.shouldApplyIncomingDueDate(date, to: item) {
                    mutate(item, repo: repo) { headline, _ in
                        ReminderSyncRules.applyIncomingDueDate(date, to: &headline)
                    }
                }
            }

            // Re-read the notes after inbound mutations, then mirror their
            // current state out to Reminders.
            let items = repo.allTodoItems().filter { $0.outline.filePath != CalendarSyncRules.fileName }
            for item in items where item.scheduled != nil || item.deadline != nil || mappings[key(item)] != nil {
                let mapKey = key(item)
                let reminder = mappings[mapKey].flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
                    ?? EKReminder(eventStore: store)
                reminder.calendar = list
                reminder.title = item.title
                reminder.notes = noteMetadata(item.outline)
                reminder.priority = ReminderSyncRules.priority(for: item.priority)
                reminder.dueDateComponents = ReminderSyncRules.dueDateComponents(for: item)
                reminder.recurrenceRules = ReminderSyncRules.recurrenceRules(for: item)
                reminder.isCompleted = item.isDone
                try store.save(reminder, commit: false)
                mappings[mapKey] = reminder.calendarItemIdentifier
            }
            try store.commit()
            saveMappings(mappings)
            repo.refresh()
        } catch { lastError = error.localizedDescription }
    }

    private func orgSyncList() throws -> EKCalendar {
        let id = settings.remindersListID
        if !id.isEmpty, let list = store.calendar(withIdentifier: id) { return list }
        if let list = store.calendars(for: .reminder).first(where: { $0.title == "OrgSync" }) {
            settings.remindersListID = list.calendarIdentifier; return list
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = "OrgSync"
        guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first else { throw NSError(domain: "OrgSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Reminders account is available."]) }
        list.source = source
        try store.saveCalendar(list, commit: true)
        settings.remindersListID = list.calendarIdentifier
        lists = store.calendars(for: .reminder)
        return list
    }

    private func fetchReminders(_ predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
    }

    private func ensurePersistentIDs(repo: RepoStore) {
        repo.performMutationBatch {
            // Never write :ID: drawers into the regenerated calendar mirror.
            for file in repo.allOrgFiles() where file.relativePath != CalendarSyncRules.fileName {
                var document = repo.document(of: file)
                if document.ensurePersistentIDsForTodoHeadlines() {
                    _ = repo.write(document.serialize(), to: file)
                }
            }
        }
    }

    private func mutate(_ item: OrgTodoItem, repo: RepoStore, _ transform: (inout OrgHeadline, OrgDocument) -> Void) {
        guard let file = repo.item(forRelativePath: item.outline.filePath) else { return }
        var document = repo.document(of: file); let original = document
        guard document.mutateHeadline(at: item.outline, { transform(&$0, original) }) else { return }
        _ = repo.write(document.serialize(), to: file)
    }
    /// A reminder created directly in the dedicated list becomes a TODO in the
    /// local inbox. Its stable outline is immediately added to the mapping.
    private func createInboxTodo(from reminder: EKReminder, repo: RepoStore) -> OrgOutline? {
        let file = repo.item(forRelativePath: "inbox.org") ?? repo.createNote(named: "inbox", in: repo.repoURL)
        guard let file else { return nil }
        let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var text = repo.text(of: file)
        if !text.hasSuffix("\n") { text += "\n" }
        text += "\n* TODO \(title)\n"
        if let components = reminder.dueDateComponents, let date = Calendar.current.date(from: components) {
            text += "SCHEDULED: \(ReminderSyncRules.inboxScheduledTimestamp(for: date).serialize())\n"
        }
        if let repeater = ReminderSyncRules.repeater(from: reminder) {
            text = ReminderSyncRules.appending(repeater: repeater, toLastScheduledTimestampIn: text)
        }
        guard repo.write(text, to: file) else { return nil }
        return repo.document(of: file).todoItems(filePath: file.relativePath)
            .last(where: { $0.title == title })?.outline
    }
    private func key(_ item: OrgTodoItem) -> String {
        if let id = item.persistentID { return "id|" + id }
        return legacyKey(item.outline)
    }
    private func legacyKey(_ outline: OrgOutline) -> String { outline.filePath + "|" + outline.headingPath.joined(separator: "\u{1F}") + "|" + String(outline.index) }
    private func loadMappings() -> [String: String] { defaults.dictionary(forKey: mappingKey) as? [String: String] ?? [:] }
    private func saveMappings(_ value: [String: String]) { defaults.set(value, forKey: mappingKey) }
    private func noteMetadata(_ outline: OrgOutline) -> String { "OrgSync\nfile: \(outline.filePath)\nheading: \(outline.headingPath.joined(separator: " / "))" }
}
