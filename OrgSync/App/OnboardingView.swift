//
//  OnboardingView.swift
//  OrgSync
//
//  A short first-run path that gives new users an immediate working model:
//  capture freely, plan from the agenda, and add GitHub sync when ready.
//

import SwiftUI

struct OnboardingView: View {
    let openInbox: () -> Void
    let connectRepository: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.15, blue: 0.34), Color(red: 0.08, green: 0.42, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            OnboardingGrid()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Text("ORG SYNC")
                    .font(.caption.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    workflowPage.tag(1)
                    syncPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                actionArea
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("onboarding.screen")
    }

    private var welcomePage: some View {
        onboardingPage(
            symbol: "sparkles",
            title: "A calmer place\nfor every thought.",
            description: "OrgSync starts with local notes that are ready for ideas, tasks, and plans—before you connect anything.",
            card: AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    Label("Everything stays on this device", systemImage: "iphone.and.arrow.forward")
                    Label("No account or tracking required", systemImage: "hand.raised.fill")
                }
                .font(.subheadline.weight(.medium))
            )
        )
    }

    private var workflowPage: some View {
        onboardingPage(
            symbol: "checklist",
            title: "Capture first.\nOrganize later.",
            description: "Use Inbox for quick thoughts, turn lines into TODOs, then let Agenda show what deserves attention today.",
            card: AnyView(
                VStack(alignment: .leading, spacing: 13) {
                    onboardingStep(number: "1", text: "Capture in Inbox")
                    onboardingStep(number: "2", text: "Add TODOs and dates")
                    onboardingStep(number: "3", text: "Work from Agenda")
                }
            )
        )
    }

    private var syncPage: some View {
        onboardingPage(
            symbol: "arrow.triangle.2.circlepath",
            title: "Your notes,\nin sync.",
            description: "When you are ready, connect a GitHub repository with a Personal Access Token. Your notes remain local-first and you stay in control.",
            card: AnyView(
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                    Text("GitHub access uses your Personal Access Token, stored securely in the Keychain.")
                        .font(.subheadline.weight(.medium))
                }
            )
        )
    }

    @ViewBuilder
    private var actionArea: some View {
        if page < 2 {
            Button(page == 0 ? "Build my system" : "One more thing") {
                withAnimation { page += 1 }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .accessibilityIdentifier("onboarding.next")
        } else {
            VStack(spacing: 12) {
                Button("Set up GitHub sync", action: connectRepository)
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding.connect")
                Button("Start with my Inbox", action: openInbox)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("onboarding.openInbox")
            }
        }
    }

    private func onboardingPage(symbol: String, title: String, description: String, card: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.45, blue: 0.76))
                .frame(width: 78, height: 78)
                .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(description)
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            card
                .foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private func onboardingStep(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.08, green: 0.35, blue: 0.65))
                .frame(width: 24, height: 24)
                .background(.white, in: Circle())
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(Color(red: 0.04, green: 0.18, blue: 0.36))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.white.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct OnboardingGrid: View {
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0, through: size.width, by: 30) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: 30) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)

            let diameter = max(size.width, size.height) * 0.9
            context.stroke(
                Path(ellipseIn: CGRect(x: -diameter * 0.3, y: size.height * 0.18, width: diameter, height: diameter)),
                with: .color(.white.opacity(0.1)),
                lineWidth: 1
            )
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    OnboardingView(openInbox: {}, connectRepository: {})
}
