//
//  BackgroundRefresh.swift
//  OrgSync
//
//  Keeps the widgets, calendar mirror, and sync state current while the app is
//  backgrounded, instead of only refreshing when the app is opened. Registered
//  with SwiftUI's `.backgroundTask(.appRefresh:)` and scheduled whenever the app
//  enters the background.
//

import BackgroundTasks
import Foundation

enum BackgroundRefresh {
    /// Must match the entry in BGTaskSchedulerPermittedIdentifiers (Info.plist).
    static let taskIdentifier = "com.memohnsen.OrgSync.refresh"

    /// Minimum spacing between background runs the system will honor. The
    /// scheduler treats this as "no earlier than", not a guarantee.
    static let minimumInterval: TimeInterval = 30 * 60

    /// Asks the system to run a refresh no sooner than `minimumInterval` from
    /// now. Safe to call repeatedly; a new request replaces the pending one.
    static func schedule(now: Date = .now) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = now.addingTimeInterval(minimumInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Performs the same catch-up work as opening the app: apply widget
    /// completions, pull remote changes, and re-mirror Reminders and calendar —
    /// each gated on its own setting. Reschedules the next run when finished.
    @MainActor
    static func run() async {
        let settings = AppServices.settings
        let repo = AppServices.repo

        WidgetCompletionReconciler.reconcile(repo: repo)

        if AppServices.sync.isConnected, settings.pullOnOpen {
            await AppServices.sync.pullNow()
            repo.refresh()
        }
        if settings.remindersSync {
            await AppServices.reminders.sync(repo: repo)
        }
        if settings.calendarSync {
            await AppServices.calendar.sync(repo: repo)
        }

        schedule()
    }
}
