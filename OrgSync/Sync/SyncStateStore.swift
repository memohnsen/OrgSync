//
//  SyncStateStore.swift
//  OrgSync
//
//  Single owner of the persisted sync baseline (`.orgsync/state.json`): its
//  location, JSON coding configuration, and load/save/delete. Both the
//  main-actor SyncEngine (which loads on launch) and the SyncWorker actor
//  (which saves after each operation) go through this type, so the path and
//  coding strategy can no longer drift between the two sides.
//

import Foundation

struct SyncStateStore: Sendable {
    let fileURL: URL

    init(repoRoot: URL) {
        fileURL = repoRoot.appendingPathComponent(".orgsync/state.json")
    }

    func load() -> SyncRepoState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(SyncRepoState.self, from: data)
    }

    /// Saves the baseline. Throwing on purpose: a silently dropped write
    /// desynchronizes the recorded baseline from the working copy, which is the
    /// single most important invariant in the sync engine.
    func save(_ state: SyncRepoState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
