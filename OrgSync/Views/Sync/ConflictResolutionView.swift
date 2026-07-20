import SwiftUI

/// Explicitly resolves pull conflict copies. Until every copy is resolved,
/// SyncEngine blocks pushes to prevent an accidental local-wins overwrite.
struct ConflictResolutionView: View {
    @Environment(SyncEngine.self) private var sync
    @State private var conflicts: [SyncEngine.ConflictCopy] = []

    var body: some View {
        List {
            if conflicts.isEmpty {
                ContentUnavailableView("No Conflicts", systemImage: "checkmark.circle",
                                       description: Text("All local and remote changes are reconciled."))
            } else {
                Section("Resolve Each File") {
                    ForEach(conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(conflict.fileName).font(.headline)
                            Text("Choose which version should remain, then sync again.")
                                .font(.caption).foregroundStyle(.secondary)
                            ConflictDiffDisclosure(conflict: conflict)
                            HStack {
                                Button("Keep Local") { sync.resolveConflictKeepingLocal(conflict); reload() }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Keep local version of \(conflict.fileName)")
                                    .accessibilityHint("Discards the remote conflicting copy for this file.")
                                Button("Use Remote", role: .destructive) { sync.resolveConflictUsingRemote(conflict); reload() }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Use remote version of \(conflict.fileName)")
                                    .accessibilityHint("Replaces the local file with the remote conflicting copy.")
                            }
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Resolve Conflicts")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
    }
    private func reload() { conflicts = sync.conflictCopies() }
}

/// Expandable inline diff between the local file (removed / red) and the incoming
/// remote conflict copy (added / green). Matches the visual style of GitChangesView.
private struct ConflictDiffDisclosure: View {
    let conflict: SyncEngine.ConflictCopy
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            Label("Local vs. Remote", systemImage: "arrow.left.arrow.right")
                .font(.caption)
        }
        .accessibilityLabel("Show differences between local and remote versions of \(conflict.fileName)")
        .accessibilityHint("Red lines are only in your local file; green lines are only in the remote copy.")
    }

    @ViewBuilder private var content: some View {
        switch (Self.readText(conflict.originalURL), Self.readText(conflict.sidecarURL)) {
        case let (.some(local), .some(remote)):
            let lines = GitInlineDiff.displayLines(original: local, current: remote)
            VStack(alignment: .leading, spacing: 0) {
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
                    .background(color(for: line.kind).opacity(backgroundOpacity(for: line.kind)),
                                in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Diff. Removed lines are local, added lines are remote.")
        default:
            Label("Binary or unreadable file", systemImage: "doc.questionmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
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
}
