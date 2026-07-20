//
//  TodoNotificationScheduler.swift
//  OrgSync
//
//  Mirrors the TodoNotificationPlanner's plan into UNUserNotificationCenter.
//  Rescheduling is wholesale: clear every pending request this app planned,
//  then register the fresh plan. Notifications live entirely on top of the org
//  files — nothing notification-related is ever written into a note.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class TodoNotificationScheduler {
    /// Mirror of the system authorization status for the Settings UI.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Prompt for permission if not yet determined. Returns whether
    /// notifications are allowed afterwards.
    @discardableResult
    func requestAuthorization() async -> Bool {
        if authorization == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await refreshAuthorization()
        return authorization == .authorized || authorization == .provisional
    }

    /// Rebuild the pending notification set from the current TODOs + settings.
    /// Safe to call often; identifiers are stable so re-adding is idempotent.
    func reschedule(repo: RepoStore, settings: SettingsStore) async {
        await refreshAuthorization()

        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(TodoNotificationPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard settings.todoNotifications,
              authorization == .authorized || authorization == .provisional else { return }

        let plan = TodoNotificationPlanner.plan(
            todos: repo.allTodoItems(),
            allDayMinutes: settings.allDayNotificationMinutes,
            timedOffsetsMinutes: settings.timedNotificationOffsets,
            now: Date()
        )

        for notification in plan {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: notification.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(
                identifier: notification.id, content: content, trigger: trigger))
        }
    }
}
