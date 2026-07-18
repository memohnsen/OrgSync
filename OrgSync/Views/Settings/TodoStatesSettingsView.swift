//
//  TodoStatesSettingsView.swift
//  OrgSync
//

import SwiftUI

struct TodoStatesSettingsView: View {
    @Binding var preference: String
    @State private var statuses: [OrgTodoStatus]
    @State private var newStatus = ""
    @State private var newStatusIsDone = false
    @State private var validationMessage: String?

    init(preference: Binding<String>) {
        _preference = preference
        _statuses = State(initialValue: OrgTodoStatusConfiguration.statuses(from: preference.wrappedValue))
    }

    var body: some View {
        List {
            statusSection(title: "Active States", isDone: false,
                          footer: "Active states appear in Agenda and cycle toward completion.")
            statusSection(title: "Completed States", isDone: true,
                          footer: "Only DONE strikes through a note title.")

            Section {
                TextField("Status name", text: $newStatus)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("todoStates.newName")
                Picker("State type", selection: $newStatusIsDone) {
                    Text("Active").tag(false)
                    Text("Completed").tag(true)
                }
                Button("Add State", action: addStatus)
                    .disabled(OrgTodoStatusConfiguration.normalizedName(newStatus) == nil)
                    .accessibilityIdentifier("todoStates.add")
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
            } header: {
                Text("Add a State")
            } footer: {
                Text("Use one word, or separate words with _ or -. Swipe a state to delete it. At least one active and completed state is always kept.")
            }
        }
        .navigationTitle("TODO States")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("todoStates.screen")
    }

    @ViewBuilder
    private func statusSection(title: String, isDone: Bool, footer: String) -> some View {
        let group = statuses.filter { $0.isDone == isDone }
        Section {
            ForEach(group) { status in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.todoStatus(status.name, configuration: configuration))
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
            Text(footer)
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
        validationMessage = nil
    }
}
