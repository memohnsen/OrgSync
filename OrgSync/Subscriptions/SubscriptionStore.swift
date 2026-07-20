//
//  SubscriptionStore.swift
//  OrgSync
//
//  RevenueCat wrapper for the OrgSync Pro subscription. The app stays
//  accountless: RevenueCat's anonymous app user ID is the only identifier —
//  no email, no sign-up, nothing linking a purchase to a person.
//
//  Configuration: put the RevenueCat public Apple API key in the app's
//  Info.plist under `RevenueCatAPIKey`. Without a key, the store reports
//  "not configured" and SubscriptionGate leaves every Pro feature unlocked.
//

import Foundation
import Observation
import RevenueCat
import WidgetKit

@MainActor
@Observable
final class SubscriptionStore {
    /// RevenueCat entitlement identifier that unlocks all Pro features.
    static let entitlementID = "pro"

    /// True when a RevenueCat API key was present and Purchases is live.
    private(set) var isConfigured = false
    /// True when the customer has the Pro entitlement.
    private(set) var hasProEntitlement = false

    /// Whether Pro features are usable right now.
    var isUnlocked: Bool {
        SubscriptionGate.isUnlocked(purchasesConfigured: isConfigured, hasProEntitlement: hasProEntitlement)
    }

    init() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
              !key.isEmpty else { return }
        // No appUserID: RevenueCat generates and persists an anonymous ID.
        Purchases.configure(withAPIKey: key)
        isConfigured = true
        // The stream delivers the current info immediately and then every
        // change — including purchases made inside RevenueCat's paywall and
        // Customer Center UI, which is why no manual purchase plumbing exists.
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        hasProEntitlement = info.entitlements[Self.entitlementID]?.isActive == true
        publishUnlockStateForWidgets()
    }

    /// Widgets run in a separate process and can't ask RevenueCat directly, so
    /// the app mirrors the unlock state into the shared app group.
    private func publishUnlockStateForWidgets() {
        let defaults = UserDefaults(suiteName: AgendaSnapshot.appGroupIdentifier)
        let previous = defaults?.object(forKey: AgendaSnapshot.proUnlockedKey) as? Bool
        guard previous != isUnlocked else { return }
        defaults?.set(isUnlocked, forKey: AgendaSnapshot.proUnlockedKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
