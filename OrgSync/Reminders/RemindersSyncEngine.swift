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
        isSyncing = true; defer { isSyncing = false }
        do {
            let list = try orgSyncList()
            var mappings = loadMappings()
            ensurePersistentIDs(repo: repo)
            let inboundItems = allTodoItems(repo: repo)
            var byKey = Dictionary(uniqueKeysWithValues: inboundItems.map { (key($0), $0) })
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
                guard let mapKey = mappings.first(where: { $0.value == reminderID })?.key,
                      let item = byKey[mapKey] else {
                    if !reminder.isCompleted, let outline = createInboxTodo(from: reminder, repo: repo) {
                        if let item = allTodoItems(repo: repo).first(where: { $0.outline == outline }) {
                            mappings[key(item)] = reminderID
                        }
                    }
                    continue
                }
                if reminder.isCompleted && !item.isDone {
                    mutate(item, repo: repo) { headline, document in
                        let done = document.todoConfig.sequences.first(where: { $0.all.contains(item.keyword) })?.done.first
                        headline.setTodoKeyword(done, config: document.todoConfig)
                    }
                }
                if let due = reminder.dueDateComponents, let date = Calendar.current.date(from: due),
                   !Calendar.current.isDate(date, inSameDayAs: relevantDate(item) ?? date) {
                    mutate(item, repo: repo) { headline, _ in
                        if headline.planning.deadline != nil && headline.planning.scheduled == nil { headline.setDeadline(date: date) }
                        else { headline.setScheduled(date: date) }
                    }
                }
            }

            // Re-read the notes after inbound mutations, then mirror their
            // current state out to Reminders.
            let items = allTodoItems(repo: repo)
            for item in items where item.scheduled != nil || item.deadline != nil || mappings[key(item)] != nil {
                let mapKey = key(item)
                let reminder = mappings[mapKey].flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
                    ?? EKReminder(eventStore: store)
                reminder.calendar = list
                reminder.title = item.title
                reminder.notes = noteMetadata(item.outline)
                reminder.priority = priority(item.priority)
                reminder.dueDateComponents = dueComponents(item)
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

    private func allTodoItems(repo: RepoStore) -> [OrgTodoItem] {
        guard let e = FileManager.default.enumerator(at: repo.repoURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "org" }.compactMap { url in
            let root = repo.repoURL.path + "/"; let path = url.path.hasPrefix(root) ? String(url.path.dropFirst(root.count)) : url.lastPathComponent
            return repo.item(forRelativePath: path)
        }.flatMap { repo.document(of: $0).todoItems(filePath: $0.relativePath) }
    }

    private func ensurePersistentIDs(repo: RepoStore) {
        guard let e = FileManager.default.enumerator(at: repo.repoURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in e where url.pathExtension.lowercased() == "org" {
            let root = repo.repoURL.path + "/"
            let path = url.path.hasPrefix(root) ? String(url.path.dropFirst(root.count)) : url.lastPathComponent
            guard let file = repo.item(forRelativePath: path) else { continue }
            var document = repo.document(of: file)
            if document.ensurePersistentIDsForTodoHeadlines() { _ = repo.write(document.serialize(), to: file) }
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
            text += "SCHEDULED: \(OrgTimestamp(date: date, isActive: true, includeTime: false).serialize())\n"
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
    private func relevantDate(_ item: OrgTodoItem) -> Date? { [item.deadline?.date(), item.scheduled?.date()].compactMap { $0 }.min() }
    private func dueComponents(_ item: OrgTodoItem) -> DateComponents? { relevantDate(item).map { Calendar.current.dateComponents([.year, .month, .day], from: $0) } }
    private func priority(_ p: Character?) -> Int { p == "A" ? 1 : p == "B" ? 5 : p == "C" ? 9 : 0 }
}
