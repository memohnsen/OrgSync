//
//  PaywallView.swift
//  OrgSync
//
//  The OrgSync Pro paywall: what's gated, the available packages from the
//  current RevenueCat offering, restore, and a privacy note reiterating the
//  app's accountless, anonymous stance. Reused as a push (Settings) and a
//  sheet (feature gates).
//

import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var subscriptions

    var body: some View {
        Form {
            Section {
                Label("Sync notes with a GitHub repository", systemImage: "arrow.triangle.branch")
                Label("Favorites and Agenda Home Screen widgets", systemImage: "square.grid.2x2")
                Label("Two-way Reminders and Calendar sync", systemImage: "checklist")
            } header: {
                Text("OrgSync Pro")
            } footer: {
                Text("Writing, organizing, agenda, search, Siri, and everything else stay free forever. iCloud Drive syncing via the notes location setting also stays free.")
            }

            if subscriptions.hasProEntitlement {
                Section {
                    Label("Pro is active — thank you!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                }
            } else if !subscriptions.isConfigured {
                Section {
                    Text("Purchases aren't available in this build. All features are unlocked.")
                        .foregroundStyle(.secondary)
                }
            } else if subscriptions.packages.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading plans…")
                    }
                }
            } else {
                Section("Plans") {
                    ForEach(subscriptions.packages, id: \.identifier) { package in
                        Button {
                            Task { await subscriptions.purchase(package) }
                        } label: {
                            LabeledContent(package.storeProduct.localizedTitle,
                                           value: package.localizedPriceString)
                        }
                        .tint(.primary)
                        .disabled(subscriptions.isPurchasing)
                        .accessibilityIdentifier("paywall.package.\(package.identifier)")
                    }
                }
            }

            if subscriptions.isConfigured, !subscriptions.hasProEntitlement {
                Section {
                    Button("Restore Purchases") {
                        Task { await subscriptions.restorePurchases() }
                    }
                    .accessibilityIdentifier("paywall.restore")
                }
            }

            if let error = subscriptions.lastError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
            } footer: {
                Text("No account needed. OrgSync stays anonymous: the only identifier attached to a subscription is a random RevenueCat ID, never your name, email, or notes.")
            }
        }
        .navigationTitle("OrgSync Pro")
        .navigationBarTitleDisplayMode(.inline)
        // iOS 27 draws a solid bar with a hard cutoff on scroll; keep the
        // pre-27 translucent look.
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await subscriptions.refresh() }
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
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
    }
}

#Preview {
    NavigationStack {
        PaywallView()
            .environment(SubscriptionStore())
    }
}
