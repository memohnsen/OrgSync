//
//  OrgSyncCommitMessage.swift
//  OrgSync
//

import Foundation

enum OrgSyncCommitMessage {
    static func automatic(date: Date = .now) -> String {
        "OrgSync update — \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    static func automatic(changeCount: Int, date: Date = .now) -> String {
        "\(automatic(date: date)) (\(changeCount) file\(changeCount == 1 ? "" : "s"))"
    }
}
