//
//  SubscriptionGate.swift
//  OrgSync
//
//  Pure gating rules for the freemium model. The core note-taking experience
//  (org editor, agenda, search, favorites, Siri) is free forever; GitHub sync,
//  Home Screen widgets, and iOS (Reminders/Calendar) sync require OrgSync Pro.
//
//  When RevenueCat is not configured (no API key in the build), every feature
//  stays unlocked: a misconfigured build must never lock users out of features
//  they already rely on.
//

import Foundation

/// The subscription-gated features.
enum ProFeature: String, CaseIterable {
    case githubSync
    case widgets
    case iosSync

    var displayName: String {
        switch self {
        case .githubSync: "GitHub Sync"
        case .widgets: "Home Screen Widgets"
        case .iosSync: "Reminders & Calendar Sync"
        }
    }
}

enum SubscriptionGate {
    /// Whether Pro features are unlocked given the store's state.
    static func isUnlocked(purchasesConfigured: Bool, hasProEntitlement: Bool) -> Bool {
        !purchasesConfigured || hasProEntitlement
    }
}
