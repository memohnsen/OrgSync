//
//  SyncError.swift
//  OrgSync
//
//  Local sync preconditions that are not GitHub API failures. Kept distinct
//  from GitHubError (which models HTTP/network outcomes) so callers can tell an
//  app-state problem from a server one, and so we stop fabricating HTTP 409/422
//  statuses for conditions that never touched the network.
//

import Foundation

enum SyncError: LocalizedError, Equatable, Sendable {
    case pendingCommitBlocksCommit
    case nothingStaged
    case noPendingCommit
    case pendingCommitBlocksDiscard
    case pendingCommitBlocksPull
    case unresolvedConflicts

    var errorDescription: String? {
        switch self {
        case .pendingCommitBlocksCommit: "Push the pending commit before creating another commit."
        case .nothingStaged: "Stage one or more changes before committing."
        case .noPendingCommit: "Create a commit before pushing."
        case .pendingCommitBlocksDiscard: "Push or discard the pending commit before discarding local changes."
        case .pendingCommitBlocksPull: "Push the pending commit before pulling remote changes."
        case .unresolvedConflicts: "Resolve conflict copies before committing and pushing."
        }
    }
}
