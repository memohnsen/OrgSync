import Foundation
import LocalAuthentication
import SwiftUI
import Testing
@testable import OrgSync

@Suite struct AppLockSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "app-lock-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func requireAppLockDefaultsOffForExistingInstalls() {
        let settings = SettingsStore(defaults: makeDefaults())
        #expect(!settings.requireAppLock)
    }

    @Test func requireAppLockPersistsAcrossLaunches() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.requireAppLock = true

        let restoredOn = SettingsStore(defaults: defaults)
        #expect(restoredOn.requireAppLock)

        restoredOn.requireAppLock = false
        let restoredOff = SettingsStore(defaults: defaults)
        #expect(!restoredOff.requireAppLock)
    }
}

@Suite struct AppLockPolicyTests {
    @Test func disabledLockIgnoresLifecycleAndStaysUnlocked() {
        for event: AppLockEvent in [
            .lifecycle(.inactive),
            .lifecycle(.background),
            .lifecycle(.active),
            .retryRequested,
            .authenticationFailed,
            .authenticationSucceeded,
        ] {
            let decision = AppLockPolicy.reduce(phase: .unlocked, isEnabled: false, event: event)
            #expect(decision.phase == .unlocked, "\(event)")
            #expect(!decision.isEnabled, "\(event)")
            #expect(decision.effect == .none, "\(event)")
        }
    }

    @Test func enabledLaunchStartsLockedUntilActive() {
        #expect(AppLockPolicy.initialPhase(isEnabled: false) == .unlocked)
        #expect(AppLockPolicy.initialPhase(isEnabled: true) == .locked)

        let inactive = AppLockPolicy.reduce(phase: .locked, isEnabled: true, event: .lifecycle(.inactive))
        #expect(inactive == AppLockDecision(phase: .locked, isEnabled: true, effect: .none))

        let background = AppLockPolicy.reduce(phase: .unlocked, isEnabled: true, event: .lifecycle(.background))
        #expect(background == AppLockDecision(phase: .locked, isEnabled: true, effect: .none))
    }

    @Test func becomingActivePromptsUnlockWhenLocked() {
        let decision = AppLockPolicy.reduce(phase: .locked, isEnabled: true, event: .lifecycle(.active))
        #expect(decision == AppLockDecision(phase: .authenticating, isEnabled: true, effect: .authenticate))
    }

    @Test func becomingActiveDoesNotRelockWhenAlreadyUnlocked() {
        let decision = AppLockPolicy.reduce(phase: .unlocked, isEnabled: true, event: .lifecycle(.active))
        #expect(decision == AppLockDecision(phase: .unlocked, isEnabled: true, effect: .none))
    }

    @Test func inactiveDuringAuthenticationKeepsThePrompt() {
        let inactive = AppLockPolicy.reduce(phase: .authenticating, isEnabled: true, event: .lifecycle(.inactive))
        #expect(inactive == AppLockDecision(phase: .authenticating, isEnabled: true, effect: .none))

        let active = AppLockPolicy.reduce(phase: .authenticating, isEnabled: true, event: .lifecycle(.active))
        #expect(active == AppLockDecision(phase: .authenticating, isEnabled: true, effect: .none))
    }

    @Test func authenticationSuccessUnlocksAndFailureStaysLocked() {
        let success = AppLockPolicy.reduce(phase: .authenticating, isEnabled: true, event: .authenticationSucceeded)
        #expect(success == AppLockDecision(phase: .unlocked, isEnabled: true, effect: .none))

        let failure = AppLockPolicy.reduce(phase: .authenticating, isEnabled: true, event: .authenticationFailed)
        #expect(failure == AppLockDecision(phase: .locked, isEnabled: true, effect: .none))
    }

    @Test func retryStartsAuthenticationAndUnavailableAuthStaysLocked() {
        let retry = AppLockPolicy.reduce(phase: .locked, isEnabled: true, event: .retryRequested)
        #expect(retry == AppLockDecision(phase: .authenticating, isEnabled: true, effect: .authenticate))

        let failedClosed = AppLockPolicy.reduce(phase: .authenticating, isEnabled: true, event: .authenticationFailed)
        #expect(failedClosed.phase == .locked)
        #expect(failedClosed.effect == .none)
    }

    @Test func turningTheSettingOffUnlocksImmediately() {
        let decision = AppLockPolicy.reduce(phase: .locked, isEnabled: true, event: .enabledChanged(false))
        #expect(decision == AppLockDecision(phase: .unlocked, isEnabled: false, effect: .none))
    }

    @Test func turningTheSettingOnDoesNotLockUntilTheSceneLeaves() {
        let decision = AppLockPolicy.reduce(phase: .unlocked, isEnabled: false, event: .enabledChanged(true))
        #expect(decision == AppLockDecision(phase: .unlocked, isEnabled: true, effect: .none))
    }
}

@Suite struct AppLockCopyTests {
    @Test func titlesAndHintsMatchBiometryType() {
        #expect(AppLockCopy.requireLockTitleKey(biometryType: .faceID) == "Require Face ID")
        #expect(AppLockCopy.requireLockTitleKey(biometryType: .touchID) == "Require Touch ID")
        #expect(AppLockCopy.requireLockTitleKey(biometryType: .opticID) == "Require Optic ID")
        #expect(AppLockCopy.requireLockTitleKey(biometryType: .none) == "Lock with Device Passcode")

        #expect(AppLockCopy.requireLockHintKey(biometryType: .faceID).contains("Face ID"))
        #expect(AppLockCopy.requireLockHintKey(biometryType: .touchID).contains("Touch ID"))
        #expect(AppLockCopy.requireLockHintKey(biometryType: .opticID).contains("Optic ID"))
        #expect(AppLockCopy.requireLockHintKey(biometryType: .none).contains("device passcode"))
        #expect(!AppLockCopy.requireLockHintKey(biometryType: .none).contains("Face ID"))
    }
}

@Suite struct AppLockControllerTests {
    @MainActor
    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test @MainActor func failedAuthenticationLeavesContentCovered() async {
        let lock = AppLockController(isEnabled: true, authenticate: { false })
        #expect(lock.coversContent)
        #expect(lock.phase == .locked)

        lock.handle(.active)
        await waitUntil { lock.phase == .locked && lock.coversContent }
        #expect(lock.phase == .locked)
        #expect(lock.coversContent)
    }

    @Test @MainActor func successfulAuthenticationRevealsContent() async {
        let lock = AppLockController(isEnabled: true, authenticate: { true })
        lock.handle(.active)
        await waitUntil { lock.phase == .unlocked }
        #expect(lock.phase == .unlocked)
        #expect(!lock.coversContent)
    }

    @Test @MainActor func enablingRequiresSuccessfulAuthentication() async {
        let rejected = AppLockController(isEnabled: false, authenticate: { false })
        let enabledAfterFailure = await rejected.setEnabled(true)
        #expect(!enabledAfterFailure)
        #expect(!rejected.isEnabled)
        #expect(!rejected.coversContent)

        let accepted = AppLockController(isEnabled: false, authenticate: { true })
        let enabledAfterSuccess = await accepted.setEnabled(true)
        #expect(enabledAfterSuccess)
        #expect(accepted.isEnabled)
        #expect(!accepted.coversContent)
    }

    @Test @MainActor func leavingTheAppCoversContentAgain() async {
        let lock = AppLockController(isEnabled: true, authenticate: { true })
        lock.handle(.active)
        await waitUntil { lock.phase == .unlocked }
        #expect(!lock.coversContent)

        lock.handle(.inactive)
        #expect(lock.coversContent)
        #expect(lock.phase == .locked)
    }
}

@Suite struct AppLockInfoPlistTests {
    @Test func faceIDUsageDescriptionIsDeclared() {
        let description = Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String ?? ""
        #expect(!description.isEmpty)
    }
}
