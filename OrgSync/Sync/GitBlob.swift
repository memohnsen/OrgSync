//
//  GitBlob.swift
//  OrgSync
//
//  Computes the git object SHA-1 for file contents locally, so the sync engine
//  can detect changes without contacting the server. Git hashes a blob as
//  `sha1("blob " + <byteCount> + "\0" + <bytes>)`; matching that exactly lets
//  us compare local files against the blob SHAs recorded in the sync state and
//  against the SHAs returned by the GitHub tree API.
//

import Foundation
import CryptoKit

nonisolated enum GitBlob {
    /// The git blob SHA-1 (40-char lowercase hex) for the given raw bytes.
    static func sha1(for data: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\0".utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Convenience: the git blob SHA-1 for UTF-8 text.
    static func sha1(for text: String) -> String {
        sha1(for: Data(text.utf8))
    }
}
