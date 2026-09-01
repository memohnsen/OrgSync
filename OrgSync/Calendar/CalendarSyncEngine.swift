//
//  CalendarSyncEngine.swift
//  OrgSync
//
//  EventKit bridge that mirrors upcoming calendar events into the read-only
//  calendar.org file. One direction only: calendar -> org. The file is
//  regenerated on every sync (app open or the Settings button), so org-side
//  edits to it never flow back to the calendar and are overwritten.
//

import EventKit
import Foundation
import Observation

@MainActor @Observable
final class CalendarSyncEngine {
    enum Access: Equatable { case unknown, denied, granted }

    private let store = EKEventStore()
    private let settings: SettingsStore

    private(set) var access: Access = .unknown
    private(set) var lastError: String?
    private(set) var isSyncing = false

    init(settings: SettingsStore) {
        self.settings = settings
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

    /// Regenerates calendar.org from the next month of events.
    func sync(repo: RepoStore) async {
        guard settings.calendarSync else { return }
        guard access == .granted else { lastError = "Allow Calendar access in Settings first."; return }
        // Regeneration is idempotent, so an overlapping run is only wasted
        // work — skip it anyway.
        guard !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }

        let window = CalendarSyncRules.window()
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate).map {
            CalendarSyncRules.Event(title: $0.title ?? "", start: $0.startDate, isAllDay: $0.isAllDay)
        }
        let rendered = CalendarSyncRules.render(events: events)

        let file = repo.item(forRelativePath: CalendarSyncRules.fileName)
            ?? repo.createNote(named: "calendar", in: repo.repoURL)
        guard let file else { lastError = "Couldn't create calendar.org."; return }
        // Skip the write (and the repo-wide refresh it triggers) when the
        // mirror is already current.
        if repo.text(of: file) != rendered {
            guard repo.write(rendered, to: file) else {
                lastError = "Couldn't update calendar.org."
                return
            }
        }
    }
}
