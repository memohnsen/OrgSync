//
//  OrgSyncApp.swift
//  OrgSync
//
//  Created by Maddisen Mohnsen on 7/18/26.
//

import SwiftUI
import AppIntents
import OrgSyncIntents

@main
struct OrgSyncApp: App {
    @UIApplicationDelegateAdaptor(OrgSyncAppDelegate.self) private var appDelegate

    init() {
        AppDependencyManager.shared.add(dependency: PullChangesPerformer {
            let sync = AppServices.sync
            guard sync.isConnected else { return .notConnected }
            await sync.pullNow()
            if let error = sync.lastError { return .failure(error) }
            return .success
        })
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.run()
        }
    }
}
