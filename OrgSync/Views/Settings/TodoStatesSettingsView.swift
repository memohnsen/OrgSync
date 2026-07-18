//
//  TodoStatesSettingsView.swift
//  OrgSync
//

import SwiftUI

struct TodoStatesSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var preference: String
    @State private var statuses: [OrgTodoStatus]
    @State private var newStatus = ""
    @State private var newStatusIsDone = false
    @State private var newStatusColor = OrgTodoStatusPalette.customColors[0].hex
    @State private var validationMessage: String?

    init(preference: Binding<String>) {
        _preference = preference
        _statuses = State(initialValue: OrgTodoStatusConfiguration.statuses(from: preference.wrappedValue))
    }

    var body: some View {
        List {
            statusSection(title: "Active Statuses", isDone: false,
                          footer: "TODO, PROGRESS, and WAITING are active by default. Active statuses appear in Agenda and cycle toward completion.")
            statusSection(title: "Completed Statuses", isDone: true)

            Section {
                TextField("Status name", text: $newStatus)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("todoStates.newName")
                Picker("Status type", selection: $newStatusIsDone) {
                    Text("Active").tag(false)
                    Text("Completed").tag(true)
                }
                Picker("Color", selection: $newStatusColor) {
                    ForEach(OrgTodoStatusPalette.customColors) { color in
                        HStack {
                            Circle().fill(color.swiftUIColor).frame(width: 12, height: 12)
                            Text(color.name)
                        }
                        .tag(color.hex)
                    }
                }
                Button("Add Status", action: addStatus)
                    .disabled(OrgTodoStatusConfiguration.normalizedName(newStatus) == nil)
                    .accessibilityIdentifier("todoStates.add")
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
            } header: {
                Text("Add a Status")
            } footer: {
                Text("Choose a color for each custom status. Use one word, or separate words with _ or -. Swipe a status to delete it. At least one active and completed status is always kept.")
            }
        }
        .navigationTitle("TODO Statuses")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("todoStates.screen")
    }

    @ViewBuilder
    private func statusSection(title: String, isDone: Bool, footer: String? = nil) -> some View {
        let group = statuses.filter { $0.isDone == isDone }
        Section {
            ForEach(group) { status in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.todoStatus(status.name, configuration: configuration, overrides: settings.todoStatusColors))
                        .frame(width: 10, height: 10)
                    Text(status.name)
                    Spacer()
                    if status.name == "DONE" {
                        Text("Strikethrough")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(status.name), \(isDone ? "completed" : "active") status")
                .swipeActions {
                    Button(role: .destructive) { remove(status) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(group.count == 1)
                }
            }
        } header: {
            Text(title)
        } footer: {
            if let footer { Text(footer) }
        }
    }

    private var configuration: OrgTodoConfig {
        OrgTodoConfig(sequences: [OrgTodoConfig.parseSequence(preference)])
    }

    private func addStatus() {
        guard let updated = OrgTodoStatusConfiguration.adding(newStatus, isDone: newStatusIsDone, to: statuses) else {
            validationMessage = "Use a unique, single-word status name."
            return
        }
        statuses = updated
        preference = OrgTodoStatusConfiguration.preference(from: updated)
        settings.todoStatusColors[updated.last!.name] = newStatusColor
        newStatus = ""
        validationMessage = nil
    }

    private func remove(_ status: OrgTodoStatus) {
        let updated = OrgTodoStatusConfiguration.removing(status, from: statuses)
        guard updated != statuses else {
            validationMessage = "Keep at least one \(status.isDone ? "completed" : "active") state."
            return
        }
        statuses = updated
        preference = OrgTodoStatusConfiguration.preference(from: updated)
        settings.todoStatusColors.removeValue(forKey: status.name)
        validationMessage = nil
    }
}

private extension OrgTodoStatusPalette.CustomColor {
    var swiftUIColor: Color {
        Color.todoStatus("CUSTOM", configuration: .default, overrides: ["CUSTOM": hex])
    }
}
