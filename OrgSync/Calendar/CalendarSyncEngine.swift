//
//  CalendarSyncEngine.swift
//  OrgSync
//
//  EventKit bridge for calendar.org. Direction follows settings.calendarMasterSource:
//  iOS Calendar master mirrors events into calendar.org; calendar.org master
//  reconciles a managed OrgSync calendar from the file.
//

import EventKit
import Foundation
import Observation

@MainActor @Observable
final class CalendarSyncEngine {
    enum Access: Equatable { case unknown, denied, granted }

    private let store = EKEventStore()
    private let settings: SettingsStore
    private let defaults: UserDefaults
    private let mappingKey = "calendar.orgIDToEventIdentifier"

    private(set) var access: Access = .unknown
    private(set) var lastError: String?
    private(set) var isSyncing = false

    init(settings: SettingsStore) {
        self.settings = settings
        self.defaults = UserDefaults(suiteName: AgendaSnapshot.appGroupIdentifier) ?? .standard
        refreshAccess()
    }

    func refreshAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        access = status == .fullAccess ? .granted : status == .denied ? .denied : .unknown
    }

    func clearError() { lastError = nil }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            refreshAccess()
            if !granted { lastError = "Calendar access was not granted." }
        } catch { lastError = error.localizedDescription; refreshAccess() }
    }

    func sync(repo: RepoStore) async {
        guard settings.calendarSync else { return }
        guard access == .granted else { lastError = "Allow Calendar access in Settings first."; return }
        guard !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }

        do {
            for phase in CalendarSyncRules.calendarPhases(for: settings.calendarMasterSource) {
                switch phase {
                case .importFromIOS:
                    try importFromIOS(repo: repo)
                case .exportToIOS:
                    try exportToIOS(repo: repo)
                }
            }
        } catch { lastError = error.localizedDescription }
    }

    private func importFromIOS(repo: RepoStore) throws {
        let window = CalendarSyncRules.window()
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let fetched = store.events(matching: predicate)
        var mappings = loadMappings()
        var events: [CalendarSyncRules.Event] = []
        var seenEventIDs = Set<String>()

        for ekEvent in fetched {
            let eventID = ekEvent.calendarItemIdentifier
            seenEventIDs.insert(eventID)
            let orgID = mappings.first(where: { $0.value == eventID })?.key
                ?? UUID().uuidString.uppercased()
            mappings[orgID] = eventID
            events.append(CalendarSyncRules.Event(
                persistentID: orgID,
                title: ekEvent.title ?? "",
                start: ekEvent.startDate,
                isAllDay: ekEvent.isAllDay
            ))
        }

        mappings = mappings.filter { _, eventID in seenEventIDs.contains(eventID) }
        let rendered = CalendarSyncRules.render(events: events, orgIsMaster: false)
        try writeCalendarOrg(rendered, repo: repo)
        saveMappings(mappings)
    }

    private func exportToIOS(repo: RepoStore) throws {
        ensurePersistentIDs(repo: repo)
        let file = calendarOrgFile(in: repo)
        guard let file else { throw syncError("Couldn't open calendar.org.") }
        var mappings = loadMappings()
        let orgEvents = CalendarSyncRules.events(inWindowFrom: repo.document(of: file))
        let list = try orgSyncCalendar()
        var seenOrgIDs = Set<String>()

        for event in orgEvents {
            guard let orgID = event.persistentID else { continue }
            seenOrgIDs.insert(orgID)
            let ekEvent = mappings[orgID].flatMap { store.event(withIdentifier: $0) }
                ?? EKEvent(eventStore: store)
            ekEvent.calendar = list
            ekEvent.title = event.title
            ekEvent.startDate = event.start
            ekEvent.isAllDay = event.isAllDay
            ekEvent.endDate = endDate(for: event)
            try store.save(ekEvent, span: .thisEvent, commit: false)
            mappings[orgID] = ekEvent.eventIdentifier
        }

        for (orgID, eventID) in mappings where !seenOrgIDs.contains(orgID) {
            if let ekEvent = store.event(withIdentifier: eventID) {
                try store.remove(ekEvent, span: .thisEvent, commit: false)
            }
            mappings.removeValue(forKey: orgID)
        }

        try store.commit()
        saveMappings(mappings)
        repo.refresh()
    }

    private func endDate(for event: CalendarSyncRules.Event) -> Date {
        if event.isAllDay {
            return Calendar.current.date(byAdding: .day, value: 1, to: event.start) ?? event.start
        }
        return Calendar.current.date(byAdding: .hour, value: 1, to: event.start) ?? event.start
    }

    private func writeCalendarOrg(_ rendered: String, repo: RepoStore) throws {
        let file = calendarOrgFile(in: repo) ?? repo.createNote(named: "calendar", in: repo.repoURL)
        guard let file else { throw syncError("Couldn't create calendar.org.") }
        if repo.text(of: file) != rendered {
            guard repo.write(rendered, to: file) else {
                throw syncError("Couldn't update calendar.org.")
            }
        }
    }

    private func calendarOrgFile(in repo: RepoStore) -> FileItem? {
        repo.item(forRelativePath: CalendarSyncRules.fileName)
    }

    private func ensurePersistentIDs(repo: RepoStore) {
        guard let file = calendarOrgFile(in: repo) else { return }
        var document = repo.document(of: file)
        guard document.ensurePersistentIDsForTodoHeadlines() else { return }
        _ = repo.write(document.serialize(), to: file)
    }

    private func orgSyncCalendar() throws -> EKCalendar {
        if let list = store.calendars(for: .event).first(where: { $0.title == CalendarSyncRules.managedCalendarTitle }) {
            return list
        }
        let list = EKCalendar(for: .event, eventStore: store)
        list.title = CalendarSyncRules.managedCalendarTitle
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first else {
            throw syncError("No Calendar account is available.")
        }
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    private func loadMappings() -> [String: String] {
        defaults.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
    }

    private func saveMappings(_ value: [String: String]) {
        defaults.set(value, forKey: mappingKey)
    }

    private func syncError(_ message: String) -> NSError {
        NSError(domain: "OrgSync", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
