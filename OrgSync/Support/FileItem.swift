//
//  FileItem.swift
//  OrgSync
//
//  Lightweight value type describing a single entry (folder or `.org` file)
//  in the local repo mirror. Carries just enough metadata for the browser UI.
//

import Foundation

struct FileItem: Identifiable, Hashable {
    /// Absolute file-system URL of the entry.
    let url: URL
    /// Path relative to the repo root, used as a stable identifier for
    /// favorites and navigation (e.g. `notes/reading.org`).
    let relativePath: String
    let isDirectory: Bool
    let modifiedDate: Date

    var id: String { relativePath }
    var name: String { url.lastPathComponent }

    /// Display name without the `.org` extension for files.
    var displayName: String {
        isDirectory ? name : (url.deletingPathExtension().lastPathComponent)
    }

    var isOrgFile: Bool {
        !isDirectory && url.pathExtension.lowercased() == "org"
    }
}
