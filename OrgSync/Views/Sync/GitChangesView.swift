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
                            inlineDiff(for: diff)
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

    private func inlineDiff(for diff: GitFileDiff) -> some View {
        let lines = GitInlineDiff.displayLines(original: diff.original, current: diff.current)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(marker(for: line.kind))
                        .foregroundStyle(color(for: line.kind))
                        .frame(width: 12)
                    Text(line.text.isEmpty ? " " : line.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color(for: line.kind).opacity(backgroundOpacity(for: line.kind)), in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    private func marker(for kind: GitInlineDiff.Line.Kind) -> String {
        switch kind { case .unchanged: return " "; case .removed: return "−"; case .added: return "+"; case .collapsed: return "⋯" }
    }

    private func color(for kind: GitInlineDiff.Line.Kind) -> Color {
        switch kind { case .unchanged: return .primary; case .removed: return .red; case .added: return .green; case .collapsed: return .secondary }
    }

    private func backgroundOpacity(for kind: GitInlineDiff.Line.Kind) -> Double {
        switch kind { case .unchanged, .collapsed: return 0; case .removed, .added: return 0.16 }
    }

    private func load() async {
        defer { isLoading = false }
        do { diffs = try await sync.localDiffs() }
        catch { self.error = error.localizedDescription }
    }
}
