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
                                Button("Use Remote", role: .destructive) { sync.resolveConflictUsingRemote(conflict); reload() }
                                    .buttonStyle(.bordered)
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
