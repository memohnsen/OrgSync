//
//  OrgEditorToolbarCustomizationView.swift
//  OrgSync
//

import SwiftUI

struct OrgEditorToolbarCustomizationView: View {
    @Binding var commands: [OrgEditorCommand]
    @Environment(\.dismiss) private var dismiss

    private var availableCommands: [OrgEditorCommand] {
        OrgEditorCommand.allCases.filter { !commands.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(commands) { command in
                        Label(command.title, systemImage: command.symbol)
                            .accessibilityIdentifier("editor.toolbar.command.\(command.rawValue)")
                    }
                    .onDelete { commands.remove(atOffsets: $0) }
                    .onMove { commands.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Shown in Toolbar")
                } footer: {
                    Text("Drag to reorder. Remove a command to hide it from the keyboard toolbar.")
                }

                if !availableCommands.isEmpty {
                    Section("Add Commands") {
                        ForEach(availableCommands) { command in
                            Button {
                                commands.append(command)
                            } label: {
                                Label(command.title, systemImage: command.symbol)
                            }
                            .accessibilityIdentifier("editor.toolbar.add.\(command.rawValue)")
                        }
                    }
                }
            }
            .navigationTitle("Edit Toolbar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
