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
