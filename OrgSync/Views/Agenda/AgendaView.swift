//
//  AgendaView.swift
//  OrgSync
//
//  Aggregates open org TODOs from every note into Today, Upcoming, and All
//  views. Changes are made against the original document through its outline
//  address, keeping the agenda a view over notes rather than a second database.
//

import SwiftUI

struct AgendaView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case today = "Today"
        case upcoming = "Upcoming"
        case all = "All"
        var id: String { rawValue }
    }

    @Environment(RepoStore.self) private var repo
    @Environment(SettingsStore.self) private var settings
    @Environment(RemindersSyncEngine.self) private var reminders
    @State private var scope: Scope = .today
    @State private var items: [OrgTodoItem] = []
    @State private var rescheduling: OrgTodoItem?
    @State private var rescheduleDate = Date()
    @State private var showQuickAdd = false
    @State private var quickAddTitle = ""
    @State private var quickAddStatus = "TODO"
    @State private var quickAddTags = ""
    @State private var includesScheduledDate = false
    @State private var scheduledDate = Date()
    @State private var includesDeadlineDate = false
    @State private var deadlineDate = Date()

    var body: some View {
        NavigationStack {
            List {
                Picker("Agenda View", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityIdentifier("agenda.scope")
                .accessibilityLabel("Agenda View")
                .accessibilityHint("Choose today, upcoming, or all open tasks.")

                if visibleSections.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "calendar",
                                           description: Text(emptyDescription))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(visibleSections) { section in
                        Section(section.title) {
                            ForEach(section.items, id: \.outline) { item in
                                row(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { beginQuickAdd() } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add agenda item")
                    .accessibilityIdentifier("agenda.add")
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("agenda.screen")
            .refreshable { reload() }
            .task(id: repo.revision) { reload() }
            .sheet(item: $rescheduling) { item in
                NavigationStack {
                    Form {
                        DatePicker("Date", selection: $rescheduleDate, displayedComponents: .date)
                            .accessibilityIdentifier("agenda.rescheduleDate")
                    }
                    .navigationTitle("Reschedule")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { rescheduling = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { reschedule(item, to: rescheduleDate) }
                        }
                    }
                }
            }
            .sheet(isPresented: $showQuickAdd) {
                NavigationStack {
                    Form {
                        TextField("Title", text: $quickAddTitle)
                            .accessibilityIdentifier("agenda.quickAddTitle")
                        Picker("State", selection: $quickAddStatus) {
                            ForEach(availableStatuses, id: \.name) { status in
                                Text(status.name).tag(status.name)
                            }
                        }
                        .accessibilityIdentifier("agenda.quickAddStatus")
                        TextField("Tags", text: $quickAddTags, prompt: Text("work, personal"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("agenda.quickAddTags")

                        Section("Schedule") {
                            Toggle("Scheduled", isOn: $includesScheduledDate)
                                .accessibilityIdentifier("agenda.quickAddScheduled")
                            if includesScheduledDate {
                                DatePicker("Scheduled Date", selection: $scheduledDate, displayedComponents: .date)
                                    .accessibilityIdentifier("agenda.quickAddScheduledDate")
                            }
                            Toggle("Deadline", isOn: $includesDeadlineDate)
                                .accessibilityIdentifier("agenda.quickAddDeadline")
                            if includesDeadlineDate {
                                DatePicker("Deadline Date", selection: $deadlineDate, displayedComponents: .date)
                                    .accessibilityIdentifier("agenda.quickAddDeadlineDate")
                            }
                        }
                    }
                    .navigationTitle("New Agenda Item")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showQuickAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") { addQuickItem() }
                                .disabled(quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("agenda.quickAddConfirm")
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private func row(_ item: OrgTodoItem) -> some View {
        if let file = repo.item(forRelativePath: item.outline.filePath) {
            NavigationLink {
                NoteDetailView(item: file)
            } label: {
                rowContent(item)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { complete(item) } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button { beginReschedule(item) } label: {
                    Label("Reschedule", systemImage: "calendar")
                }
                .tint(.blue)
            }
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: OrgTodoItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                statusChip(for: item)
                if let priority = item.priority {
                    Text("#\(String(priority))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(priority == "A" ? .red : priority == "B" ? .orange : .blue)
                }
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(item.outline.filePath)
                if let dateLabel = dateLabel(for: item) {
                    Text("·")
                    Text(dateLabel)
                        .foregroundStyle(dateColor(for: item))
                }
                if !item.tags.isEmpty {
                    Text("·")
                    Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityHint("Swipe right to complete or left to reschedule. Double tap to open note.")
    }

    private func statusChip(for item: OrgTodoItem) -> some View {
        let color = statusColor(for: item)
        return Text(item.keyword)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("Status \(item.keyword)")
    }

    // MARK: - Data

    private struct AgendaSection: Identifiable {
        var title: String
        var items: [OrgTodoItem]
        var id: String { title }
    }

    private var visibleSections: [AgendaSection] {
        switch scope {
        case .today:
            let today = Calendar.current.startOfDay(for: .now)
            let due = items.filter { isTodayOrOverdue($0, relativeTo: today) }
                .sorted(by: agendaSort)
            return due.isEmpty ? [] : [AgendaSection(title: "Today", items: due)]
        case .upcoming:
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: .now)
            let end = calendar.date(byAdding: .day, value: settings.agendaDays + 1, to: start)!
            let due = items.filter { item in
                guard let date = relevantDate(item) else { return false }
                return date >= start && date < end
            }.sorted(by: agendaSort)
            return due.isEmpty ? [] : [AgendaSection(title: "Next \(settings.agendaDays) Days", items: due)]
        case .all:
            let grouped = Dictionary(grouping: items, by: \.outline.filePath)
            return grouped.keys.sorted().map { path in
                AgendaSection(title: path, items: grouped[path, default: []].sorted(by: agendaSort))
            }
        }
    }

    private var emptyTitle: String {
        switch scope {
        case .today: return "Nothing Due Today"
        case .upcoming: return "Nothing Upcoming"
        case .all: return "No Open TODOs"
        }
    }

    private var emptyDescription: String {
        scope == .all ? "Add TODO headlines to an org file to see them here."
                      : "Scheduled and deadline items from your notes will appear here."
    }

    private func reload() {
        let discovered = repo.allTodoItems().filter { !OrgTodoStatusPalette.isCompleted($0.keyword) }
        items = discovered
        // Snapshot refresh is centralized in RepoStore mutations; retain this
        // direct write for an Agenda refresh when nothing has changed locally.
        AgendaSnapshotWriter.write(discovered)
    }

    // MARK: - Actions

    private var availableStatuses: [OrgTodoStatus] {
        OrgTodoStatusConfiguration.statuses(from: settings.todoKeywords)
    }

    private func beginQuickAdd() {
        quickAddTitle = ""
        quickAddStatus = availableStatuses.first(where: { !$0.isDone })?.name ?? availableStatuses.first?.name ?? "TODO"
        quickAddTags = ""
        includesScheduledDate = false
        scheduledDate = .now
        includesDeadlineDate = false
        deadlineDate = .now
        showQuickAdd = true
    }

    private func addQuickItem() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let status = availableStatuses.contains(where: { $0.name == quickAddStatus }) ? quickAddStatus : "TODO"
        let tags = normalizedTags(quickAddTags)
        let tagSuffix = tags.isEmpty ? "" : " :" + tags.joined(separator: ":") + ":"

        guard let inbox = repo.item(forRelativePath: "inbox.org") ?? repo.createNote(named: "inbox", in: repo.repoURL) else { return }
        var text = repo.text(of: inbox)
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += "* \(status) \(title)\(tagSuffix)\n"
        if includesScheduledDate {
            text += "SCHEDULED: \(OrgTimestamp(date: scheduledDate, isActive: true, includeTime: false).serialize())\n"
        }
        if includesDeadlineDate {
            text += "DEADLINE: \(OrgTimestamp(date: deadlineDate, isActive: true, includeTime: false).serialize())\n"
        }
        guard repo.write(text, to: inbox) else { return }
        showQuickAdd = false
        reload()
        if settings.remindersSync {
            Task { await reminders.sync(repo: repo) }
        }
    }

    private func normalizedTags(_ text: String) -> [String] {
        Array(Set(text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ":")) }
            .filter { !$0.isEmpty }))
            .sorted()
    }

    private func complete(_ item: OrgTodoItem) {
        mutate(item) { headline, document in
            ReminderSyncRules.complete(&headline, item: item, document: document)
        }
    }

    private func beginReschedule(_ item: OrgTodoItem) {
        rescheduleDate = relevantDate(item) ?? .now
        rescheduling = item
    }

    private func reschedule(_ item: OrgTodoItem, to date: Date) {
        mutate(item) { headline, _ in
            ReminderSyncRules.applyIncomingDueDate(date, to: &headline)
        }
        rescheduling = nil
    }

    private func mutate(_ item: OrgTodoItem,
                        _ transform: (inout OrgHeadline, OrgDocument) -> Void) {
        guard let file = repo.item(forRelativePath: item.outline.filePath) else { return }
        var document = repo.document(of: file)
        let original = document
        guard document.mutateHeadline(at: item.outline, { transform(&$0, original) }) else { return }
        _ = repo.write(document.serialize(), to: file)
        reload()
    }

    // MARK: - Date logic

    private func relevantDate(_ item: OrgTodoItem) -> Date? {
        ReminderSyncRules.relevantDate(for: item)
    }

    private func isTodayOrOverdue(_ item: OrgTodoItem, relativeTo today: Date) -> Bool {
        guard let date = relevantDate(item) else { return false }
        return date < Calendar.current.date(byAdding: .day, value: 1, to: today)!
    }

    private func agendaSort(_ lhs: OrgTodoItem, _ rhs: OrgTodoItem) -> Bool {
        switch (relevantDate(lhs), relevantDate(rhs)) {
        case let (a?, b?): return a == b ? lhs.title < rhs.title : a < b
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.title < rhs.title
        }
    }

    private func dateLabel(for item: OrgTodoItem) -> String? {
        guard let date = relevantDate(item) else { return nil }
        let prefix = item.deadline?.date() == date ? "Due " : "Scheduled "
        return prefix + date.formatted(.relative(presentation: .named))
    }

    private func dateColor(for item: OrgTodoItem) -> Color {
        guard let date = relevantDate(item) else { return .secondary }
        return date < Calendar.current.startOfDay(for: .now) ? .red : .secondary
    }

    private func statusColor(for item: OrgTodoItem) -> Color {
        guard let file = repo.item(forRelativePath: item.outline.filePath) else {
            return .todoStatus(item.keyword, configuration: .default, overrides: settings.todoStatusColors)
        }
        return .todoStatus(item.keyword, configuration: repo.document(of: file).todoConfig,
                           overrides: settings.todoStatusColors)
    }

    private func accessibilityLabel(for item: OrgTodoItem) -> String {
        var parts = [item.keyword, item.title]
        if let priority = item.priority { parts.append("priority \(priority)") }
        if let dateLabel = dateLabel(for: item) { parts.append(dateLabel) }
        if !item.tags.isEmpty { parts.append("tags \(item.tags.joined(separator: ", "))") }
        parts.append("in \(item.outline.filePath)")
        return parts.joined(separator: ", ")
    }
}

#Preview {
    AgendaView()
        .environment(RepoStore())
        .environment(FavoritesStore())
}
