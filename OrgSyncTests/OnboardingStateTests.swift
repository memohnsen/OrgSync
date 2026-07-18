import Foundation
import Testing
@testable import OrgSync

@Suite struct OnboardingStateTests {
    @Test func firstLaunchPresentsOnboardingAndFinishingPersistsIt() {
        let suiteName = "OrgSyncTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunch = OnboardingState(defaults: defaults, launchArguments: [])
        #expect(firstLaunch.isPresented)

        firstLaunch.finish()
        #expect(!firstLaunch.isPresented)

        let laterLaunch = OnboardingState(defaults: defaults, launchArguments: [])
        #expect(!laterLaunch.isPresented)
    }

    @Test func restartMakesCompletedOnboardingAvailableAgain() {
        let suiteName = "OrgSyncTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = OnboardingState(defaults: defaults, launchArguments: [])
        state.finish()
        state.restart()

        #expect(state.isPresented)
        let nextLaunch = OnboardingState(defaults: defaults, launchArguments: [])
        #expect(nextLaunch.isPresented)
    }

    @Test func uiTestingArgumentsCanShowOrSkipOnboarding() {
        let suiteName = "OrgSyncTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "onboarding.completed")
        #expect(OnboardingState(defaults: defaults, launchArguments: ["-ui-testing-show-onboarding"]).isPresented)
        #expect(!OnboardingState(defaults: defaults, launchArguments: ["-ui-testing-skip-onboarding"]).isPresented)
    }
}
