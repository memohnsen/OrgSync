//
//  ConflictSidecar.swift
//  OrgSync
//
//  The one place that knows the conflict-copy filename convention
//  (`name (conflict <sha7>).ext`). A merge conflict writes the remote version
//  beside the local file under this name; the sync engine detects and resolves
//  them by it. Previously the format was written, matched, and reverse-parsed
//  by hand in three separate places, so any change silently broke detection.
//

import Foundation

enum ConflictSidecar {
    private static let marker = " (conflict "

    /// Sidecar file name for a conflicted file, tagged with the remote SHA.
    static func name(for fileName: String, remoteSHA: String) -> String {
        let (base, ext) = split(fileName)
        let tagged = "\(base)\(marker)\(remoteSHA.prefix(7)))"
        return ext.isEmpty ? tagged : "\(tagged).\(ext)"
    }

    /// Whether a file name — or a relative path containing one — is a sidecar.
    static func isSidecar(_ nameOrPath: String) -> Bool {
        nameOrPath.contains(marker)
    }

    /// The original file name a sidecar was derived from, or nil if not one.
    static func originalName(ofSidecar fileName: String) -> String? {
        let (stem, ext) = split(fileName)
        guard let range = stem.range(of: marker, options: .backwards) else { return nil }
        let originalStem = String(stem[..<range.lowerBound])
        return ext.isEmpty ? originalStem : originalStem + "." + ext
    }

    private static func split(_ fileName: String) -> (base: String, ext: String) {
        let url = URL(fileURLWithPath: fileName)
        return (url.deletingPathExtension().lastPathComponent, url.pathExtension)
    }
}
