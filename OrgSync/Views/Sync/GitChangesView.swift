//
//  GitChangesView.swift
//  OrgSync
//

import SwiftUI

struct GitChangesView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var diffs: [GitFileDiff] = []
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack { Spacer(); ProgressView("Loading changes…"); Spacer() }
                } else if let error {
                    ContentUnavailableView("Unable to Load Changes", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else if diffs.isEmpty {
                    ContentUnavailableView("No Local Changes", systemImage: "checkmark.circle")
                } else {
                    ForEach(diffs) { diff in
                        Section {
                            if let original = diff.original {
                                content(original, label: diff.kind == .deleted ? "Deleted content" : "Original", color: .red)
                            }
                            if let current = diff.current {
                                content(current, label: diff.kind == .added ? "Added content" : "Current", color: .green)
                            }
                        } header: {
                            HStack {
                                Text(diff.path)
                                Spacer()
                                Text(diff.kind.rawValue.capitalized)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }

    private func content(_ text: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(text.isEmpty ? "(empty)" : text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() async {
        defer { isLoading = false }
        do { diffs = try await sync.localDiffs() }
        catch { self.error = error.localizedDescription }
    }
}
