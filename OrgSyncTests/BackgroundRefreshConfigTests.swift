//
//  BackgroundRefreshConfigTests.swift
//  OrgSyncTests
//
//  Guards the background-refresh wiring: the code's task identifier must be in
//  the app's BGTaskSchedulerPermittedIdentifiers, and the fetch background mode
//  must be declared — a mismatch fails silently at runtime.
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct BackgroundRefreshConfigTests {
    @Test func taskIdentifierIsPermittedInInfoPlist() {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        #expect(permitted.contains(BackgroundRefresh.taskIdentifier))
    }

    @Test func fetchBackgroundModeIsDeclared() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        #expect(modes.contains("fetch"))
    }
}
