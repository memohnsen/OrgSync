//
//  AppReviewPrompter.swift
//  OrgSync
//
//  Controls the two intentional points at which OrgSync asks iOS to consider
//  showing an App Store review prompt. iOS retains final control over whether a
//  prompt appears and may suppress it according to system rate limits.
//

import StoreKit
import UIKit

enum ReviewRequestPolicy {
    private static let connectedRepositoryPromptKey = "reviewPrompt.connectedRepository"
    private static let tenthEditedNotePromptKey = "reviewPrompt.tenthEditedNote"
    private static let editedNotePathsKey = "reviewPrompt.editedNotePaths"

    static func shouldRequestAfterRepositoryConnection(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: connectedRepositoryPromptKey) else { return false }
        defaults.set(true, forKey: connectedRepositoryPromptKey)
        return true
    }

    static func shouldRequestAfterEditingNote(path: String, defaults: UserDefaults = .standard) -> Bool {
        var paths = Set(defaults.stringArray(forKey: editedNotePathsKey) ?? [])
        guard paths.insert(path).inserted else { return false }
        defaults.set(paths.sorted(), forKey: editedNotePathsKey)

        guard paths.count >= 10, !defaults.bool(forKey: tenthEditedNotePromptKey) else { return false }
        defaults.set(true, forKey: tenthEditedNotePromptKey)
        return true
    }
}

@MainActor
enum AppReviewPrompter {
    static func requestAfterRepositoryConnection() {
        requestIfEligible(ReviewRequestPolicy.shouldRequestAfterRepositoryConnection())
    }

    static func recordEditedNote(path: String) {
        requestIfEligible(ReviewRequestPolicy.shouldRequestAfterEditingNote(path: path))
    }

    private static func requestIfEligible(_ isEligible: Bool) {
        guard isEligible,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }
}
