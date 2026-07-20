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
    /// Current offering's packages, for the paywall.
    private(set) var packages: [Package] = []
    private(set) var lastError: String?
    private(set) var isPurchasing = false

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
        Task { await refresh() }
    }

    /// Re-read entitlements and the current offering.
    func refresh() async {
        guard isConfigured else { return }
        if let info = try? await Purchases.shared.customerInfo() {
            apply(info)
        }
        if let offerings = try? await Purchases.shared.offerings() {
            packages = offerings.current?.availablePackages ?? []
        }
    }

    func purchase(_ package: Package) async {
        guard isConfigured, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        lastError = nil
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled { apply(result.customerInfo) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        guard isConfigured else { return }
        lastError = nil
        do {
            apply(try await Purchases.shared.restorePurchases())
        } catch {
            lastError = error.localizedDescription
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
