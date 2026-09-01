//
//  HomeScreenQuickAction.swift
//  OrgSync
//
//  Bridges the native touch-and-hold app-icon action into the live SwiftUI
//  store graph. The scene callback may arrive before RootView exists, so the
//  request is queued by AppServices and drained after registration.
//

import SwiftUI
import UIKit

enum HomeScreenQuickAction {
    static let pullChangesType = "com.memohnsen.OrgSync.pullChanges"

    @MainActor
    static func handle(type: String) -> Bool {
        guard type == pullChangesType else { return false }
        AppServices.requestPull()
        return true
    }
}

final class OrgSyncSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            _ = HomeScreenQuickAction.handle(type: shortcutItem.type)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem
    ) async -> Bool {
        HomeScreenQuickAction.handle(type: shortcutItem.type)
    }
}

final class OrgSyncAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = OrgSyncSceneDelegate.self
        }
        return configuration
    }
}
