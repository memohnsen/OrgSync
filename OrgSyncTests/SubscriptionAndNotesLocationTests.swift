//
//  SubscriptionAndNotesLocationTests.swift
//  OrgSyncTests
//
//  Verifies the freemium gating rules and the notes-location resolution used
//  to place the repo mirror locally or in iCloud Drive.
//

import Foundation
import Testing
@testable import OrgSync

@Suite struct SubscriptionGateTests {
    @Test func entitledCustomerIsUnlocked() {
        #expect(SubscriptionGate.isUnlocked(purchasesConfigured: true, hasProEntitlement: true))
    }

    @Test func configuredWithoutEntitlementIsLocked() {
        #expect(!SubscriptionGate.isUnlocked(purchasesConfigured: true, hasProEntitlement: false))
    }

    @Test func unconfiguredBuildNeverLocksFeatures() {
        // A build without a RevenueCat key (or a config outage) must not lock
        // users out of features.
        #expect(SubscriptionGate.isUnlocked(purchasesConfigured: false, hasProEntitlement: false))
    }

    @Test func gatedFeaturesAreExactlyGitHubWidgetsAndIOSSync() {
        #expect(Set(ProFeature.allCases.map(\.rawValue)) == ["githubSync", "widgets", "iosSync"])
    }
}

@Suite struct NotesLocationTests {
    private let local = URL(fileURLWithPath: "/local/Documents", isDirectory: true)
    private let cloud = URL(fileURLWithPath: "/icloud/Documents", isDirectory: true)

    @Test func defaultsToLocalDocuments() {
        let url = NotesLocation.repoURL(useICloud: false, ubiquityDocuments: cloud, localDocuments: local)
        #expect(url.path == "/local/Documents/repo")
    }

    @Test func usesICloudWhenPreferredAndAvailable() {
        let url = NotesLocation.repoURL(useICloud: true, ubiquityDocuments: cloud, localDocuments: local)
        #expect(url.path == "/icloud/Documents/repo")
    }

    @Test func fallsBackToLocalWhenICloudUnavailable() {
        // Signed out of iCloud: preference is set but no container exists.
        let url = NotesLocation.repoURL(useICloud: true, ubiquityDocuments: nil, localDocuments: local)
        #expect(url.path == "/local/Documents/repo")
    }
}
