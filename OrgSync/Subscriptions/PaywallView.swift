//
//  PaywallView.swift
//  OrgSync
//
//  OrgSync Pro surfaces built on RevenueCatUI: the paywall configured in the
//  RevenueCat dashboard (not a hand-rolled screen) and RevenueCat's Customer
//  Center for managing an active subscription. Purchases resolve through the
//  SubscriptionStore's customer-info stream.
//

import SwiftUI
import RevenueCat
import RevenueCatUI

/// The remotely configured RevenueCat paywall, with a graceful fallback for
/// builds where purchases aren't configured.
struct ProPaywallSheet: View {
    // Optional lookup: a missing store must degrade to the fallback text, not
    // trap the environment assertion mid-presentation.
    @Environment(SubscriptionStore.self) private var subscriptions: SubscriptionStore?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let subscriptions, subscriptions.isConfigured {
            RevenueCatUI.PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { _ in dismiss() }
                .onRestoreCompleted { _ in dismiss() }
        } else {
            VStack(spacing: 12) {
                Text("Purchases aren't available in this build.")
                Text("All features are unlocked.")
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

/// Reusable locked-feature section shown in place of a gated feature's UI.
struct ProLockedSection: View {
    let feature: ProFeature
    @State private var showPaywall = false

    var body: some View {
        Section {
            Label("\(feature.displayName) requires OrgSync Pro", systemImage: "lock.fill")
                .foregroundStyle(.secondary)
            Button("Unlock with OrgSync Pro") {
                showPaywall = true
            }
            .accessibilityIdentifier("pro.unlock.\(feature.rawValue)")
            // The sheet must hang off a row, not the Section: modifying a
            // Section wraps it in a plain view, which breaks Form styling and
            // made the first presentation dismiss itself immediately.
            .sheet(isPresented: $showPaywall) {
                ProPaywallSheet()
            }
        }
    }
}

/// Presents the RevenueCat paywall once, right after onboarding finishes, for
/// customers who don't have Pro yet.
struct PostOnboardingPaywall: ViewModifier {
    let onboarding: OnboardingState
    let subscriptions: SubscriptionStore
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        content
            .onChange(of: onboarding.isPresented) { was, isNow in
                if was, !isNow, subscriptions.isConfigured, !subscriptions.hasProEntitlement {
                    showPaywall = true
                }
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallSheet()
            }
    }
}
