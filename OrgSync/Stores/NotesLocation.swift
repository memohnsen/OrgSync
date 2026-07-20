//
//  NotesLocation.swift
//  OrgSync
//
//  Where the local notes mirror lives: the app's Documents directory (default)
//  or the app's iCloud Drive container. Keeping notes in iCloud Drive gives
//  free cross-device syncing through Apple — no subscription, no GitHub —
//  because iCloud mirrors whatever files sit in that directory.
//
//  The preference is read directly from UserDefaults (not SettingsStore)
//  because RepoStore resolves its root before the settings object exists.
//

import Foundation

enum NotesLocation {
    /// UserDefaults key for the preference. True = iCloud Drive.
    static let useICloudKey = "settings.notes.useICloud"

    /// Pure resolution of the repo root from a preference + available
    /// directories. Falls back to local storage when iCloud is unavailable
    /// (signed out, Drive disabled) so the app always has a working root.
    static func repoURL(useICloud: Bool, ubiquityDocuments: URL?, localDocuments: URL) -> URL {
        if useICloud, let ubiquityDocuments {
            return ubiquityDocuments.appendingPathComponent("repo", isDirectory: true)
        }
        return localDocuments.appendingPathComponent("repo", isDirectory: true)
    }

    /// The app's iCloud Drive Documents directory, or nil when iCloud is
    /// unavailable. Blocking call; cheap after the first invocation.
    static func ubiquityDocumentsURL(fileManager: FileManager = .default) -> URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// The repo root the app should use right now.
    static func currentRepoURL(fileManager: FileManager = .default) -> URL {
        repoURL(
            useICloud: UserDefaults.standard.bool(forKey: useICloudKey),
            ubiquityDocuments: ubiquityDocumentsURL(fileManager: fileManager),
            localDocuments: fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        )
    }

    /// Move the notes directory between local storage and iCloud Drive using
    /// the ubiquitous-item API, which registers the move with the iCloud
    /// daemon. Throws with a readable message on failure. Runs file I/O, so
    /// call it off the main actor. The new location takes effect on relaunch.
    static func migrate(toICloud: Bool, fileManager: FileManager = .default) throws {
        let local = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("repo", isDirectory: true)
        guard let ubiquityDocuments = ubiquityDocumentsURL(fileManager: fileManager) else {
            throw NotesLocationError.iCloudUnavailable
        }
        let cloud = ubiquityDocuments.appendingPathComponent("repo", isDirectory: true)

        let source = toICloud ? local : cloud
        let destination = toICloud ? cloud : local
        guard fileManager.fileExists(atPath: source.path) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            throw NotesLocationError.destinationOccupied(destination.path)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try fileManager.setUbiquitous(toICloud, itemAt: source, destinationURL: destination)
    }
}

enum NotesLocationError: LocalizedError {
    case iCloudUnavailable
    case destinationOccupied(String)

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            "iCloud Drive isn't available. Sign in to iCloud and enable iCloud Drive in Settings."
        case .destinationOccupied(let path):
            "A notes folder already exists at the destination (\(path)). Move or remove it first."
        }
    }
}
