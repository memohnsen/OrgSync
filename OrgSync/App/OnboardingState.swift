//
//  OnboardingState.swift
//  OrgSync
//
//  Keeps the first-run experience separate from the tab shell, while allowing
//  debug builds to replay it from Settings.
//

import Foundation
import Observation

@Observable
final class OnboardingState {
    private static let completedKey = "onboarding.completed"

    private let defaults: UserDefaults
    var isPresented: Bool

    init(defaults: UserDefaults = .standard, launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults

        if launchArguments.contains("-ui-testing-show-onboarding") {
            isPresented = true
        } else if launchArguments.contains("-ui-testing-skip-onboarding") {
            isPresented = false
        } else {
            isPresented = !defaults.bool(forKey: Self.completedKey)
        }
    }

    func finish() {
        defaults.set(true, forKey: Self.completedKey)
        isPresented = false
    }

    func restart() {
        defaults.removeObject(forKey: Self.completedKey)
        isPresented = true
    }
}
