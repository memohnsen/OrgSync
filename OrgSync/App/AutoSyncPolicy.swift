//
//  AutoSyncPolicy.swift
//  OrgSync
//
//  Pure lifecycle policy, separated from RootView so every configuration can
//  be verified without SwiftUI scene simulation or network access.
//

import Foundation

nonisolated enum AutoSyncLifecycleEvent: Sendable {
    case active
    case inactive
}

nonisolated enum AutoSyncAction: Equatable, Sendable {
    case pull
    case pullThenSyncReminders
    case syncReminders
}

nonisolated enum AutoSyncPolicy {
    static func actions(
        for event: AutoSyncLifecycleEvent,
        autoSyncEnabled: Bool,
        isConnected: Bool,
        pullOnOpen: Bool,
        remindersSyncEnabled: Bool
    ) -> [AutoSyncAction] {
        switch event {
        case .active:
            let shouldPull = autoSyncEnabled && isConnected && pullOnOpen
            if shouldPull {
                return remindersSyncEnabled ? [.pullThenSyncReminders] : [.pull]
            }
            return remindersSyncEnabled ? [.syncReminders] : []
        case .inactive:
            return []
        }
    }
}
