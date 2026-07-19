//
//  OrgReaderView.swift
//  OrgSync
//
//  The rendered org document: a scrollable outline of styled, foldable headlines
//  with rendered body content (paragraphs with inline markup, lists with tappable
//  checkboxes, tables, src/quote/example blocks, timestamps as pills, horizontal
//  rules). Structural mutations (fold, TODO cycling, priority, checkbox toggles)
//  are surfaced to the container through `OrgReaderActions`.
//

import SwiftUI

/// Callbacks the reader invokes to mutate the underlying document. Each headline
/// is addressed by an index path (child indices from a top-level headline down).
struct OrgReaderActions {
    var cycleTodo: (_ path: [Int]) -> Void
    var setTodo: (_ path: [Int], _ keyword: String?) -> Void
    var setPriority: (_ path: [Int], _ priority: Character?) -> Void
    var toggleCheckbox: (_ path: [Int], _ contentIndex: Int, _ itemPath: [Int]) -> Void
    var togglePreambleCheckbox: (_ contentIndex: Int, _ itemPath: [Int]) -> Void
}

// MARK: - Document

struct OrgReaderView: View {
    struct BacklinkRef: Identifiable, Hashable {
        let relativePath: String
        let title: String
        var id: String { relativePath }
    }

    @Environment(SettingsStore.self) private var settings
    let document: OrgDocument
    @Binding var collapsed: Set<[Int]>
    let actions: OrgReaderActions
    var backlinks: [BacklinkRef] = []
    var onOpenBacklink: (BacklinkRef) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let title = document.title, !title.isEmpty {
                    Text(title)
                        .font(.largeTitle.bold())
                        .textSelection(.enabled)
                }
                if OrgContentBlocksView.hasVisible(document.preamble) {
                    OrgContentBlocksView(content: document.preamble,
                                         toggle: actions.togglePreambleCheckbox)
                }
                ForEach(Array(document.headlines.enumerated()), id: \.offset) { index, headline in
                    OrgHeadlineView(headline: headline, path: [index],
                                    config: document.todoConfig,
                                    statusColors: settings.todoStatusColors,
                                    collapsed: $collapsed, actions: actions)
                }
                if !backlinks.isEmpty {
                    backlinksSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var backlinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 8)
            Label("Linked References", systemImage: "link")
                .font(.headline)
                .foregroundStyle(.secondary)
            ForEach(backlinks) { ref in
                Button { onOpenBacklink(ref) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                        Text(ref.title)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note.backlink.\(ref.relativePath)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Headline

struct OrgHeadlineView: View {
    let headline: OrgHeadline
    let path: [Int]
    let config: OrgTodoConfig
    let statusColors: [String: String]
    @Binding var collapsed: Set<[Int]>
    let actions: OrgReaderActions

    private var isCollapsed: Bool { collapsed.contains(path) }
    private var hasSubtree: Bool {
        !headline.children.isEmpty || OrgContentBlocksView.hasVisible(headline.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .contextMenu { todoMenu }

            if !headline.planning.isEmpty {
                planningPills
            }

            if !isCollapsed {
                if OrgContentBlocksView.hasVisible(headline.body) {
                    OrgContentBlocksView(content: headline.body) { contentIndex, itemPath in
                        actions.toggleCheckbox(path, contentIndex, itemPath)
                    }
                }
                ForEach(Array(headline.children.enumerated()), id: \.offset) { index, child in
                    OrgHeadlineView(headline: child, path: path + [index],
                                    config: config, statusColors: statusColors,
                                    collapsed: $collapsed, actions: actions)
                }
            }
        }
        .padding(.leading, CGFloat(max(0, headline.level - 1)) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            disclosure
            if let keyword = headline.todoKeyword {
                Button { actions.cycleTodo(path) } label: {
                    Text(keyword)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(todoColor(keyword).opacity(0.18), in: Capsule())
                        .foregroundStyle(todoColor(keyword))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change TODO state for \(headline.title)")
                .accessibilityValue(keyword)
                .accessibilityHint("Double tap to cycle to the next TODO state. Long press for all states.")
            }
            if let priority = headline.priority {
                Text("#\(String(priority))")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(priorityColor(priority).opacity(0.18), in: Capsule())
                    .foregroundStyle(priorityColor(priority))
                    .accessibilityLabel("Priority \(String(priority))")
            }
            Text(titleAttributed)
                .font(titleFont)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if !headline.tags.isEmpty {
                tagChips
            }
        }
    }

    @ViewBuilder private var disclosure: some View {
        if hasSubtree {
            Button(action: toggleFold) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 20, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isCollapsed ? "Expand" : "Collapse") \(headline.title)")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityHint("Shows or hides this headline's contents.")
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 4, height: 4)
                .frame(width: 12)
        }
    }

    private var titleAttributed: AttributedString {
        var attr = OrgInlineRenderer.attributed(headline.titleInlines)
        if OrgTodoStatusPalette.shouldStrikeThrough(headline.todoKeyword) {
            attr.strikethroughStyle = Text.LineStyle.single
            attr.foregroundColor = .secondary
        }
        return attr
    }

    private var tagChips: some View {
        HStack(spacing: 4) {
            ForEach(headline.tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Tag \(tag)")
            }
        }
    }

    private var planningPills: some View {
        HStack(spacing: 6) {
            if let scheduled = headline.planning.scheduled {
                TimestampPill(timestamp: scheduled, kind: .scheduled)
            }
            if let deadline = headline.planning.deadline {
                TimestampPill(timestamp: deadline, kind: .deadline)
            }
            if let closed = headline.planning.closed {
                TimestampPill(timestamp: closed, kind: .closed)
            }
        }
        .padding(.leading, 18)
    }

    @ViewBuilder private var todoMenu: some View {
        Menu("Set TODO") {
            ForEach(config.allKeywords, id: \.self) { keyword in
                Button(keyword) { actions.setTodo(path, keyword) }
            }
            if headline.todoKeyword != nil {
                Divider()
                Button("Clear TODO", role: .destructive) { actions.setTodo(path, nil) }
            }
        }
        Button {
            actions.cycleTodo(path)
        } label: {
            Label("Cycle TODO State", systemImage: "arrow.triangle.2.circlepath")
        }
        Divider()
        Menu("Priority") {
            Button("A") { actions.setPriority(path, "A") }
            Button("B") { actions.setPriority(path, "B") }
            Button("C") { actions.setPriority(path, "C") }
            if headline.priority != nil {
                Divider()
                Button("None") { actions.setPriority(path, nil) }
            }
        }
    }

    // MARK: Behaviour

    private func toggleFold() {
        guard hasSubtree else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if isCollapsed { collapsed.remove(path) } else { collapsed.insert(path) }
        }
    }

    private var titleFont: Font {
        switch headline.level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        case 4: return .subheadline.weight(.semibold)
        default: return .subheadline
        }
    }

    private func todoColor(_ keyword: String) -> Color {
        .todoStatus(keyword, configuration: config, overrides: statusColors)
    }

    private func priorityColor(_ priority: Character) -> Color {
        switch priority {
        case "A": return .red
        case "B": return .orange
        default: return .blue
        }
    }
}

// MARK: - Timestamp pill

struct TimestampPill: View {
    enum Kind { case scheduled, deadline, closed, plain }
    let timestamp: OrgTimestamp
    var kind: Kind = .plain

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption2)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kindLabel): \(label)")
    }

    private var icon: String {
        switch kind {
        case .scheduled: return "calendar"
        case .deadline: return "exclamationmark.triangle"
        case .closed: return "checkmark.circle"
        case .plain: return "calendar"
        }
    }

    private var color: Color {
        switch kind {
        case .scheduled: return .blue
        case .deadline: return isOverdue ? .red : .orange
        case .closed: return .secondary
        case .plain: return .blue
        }
    }

    private var isOverdue: Bool {
        guard let date = timestamp.date() else { return false }
        return date < Calendar.current.startOfDay(for: Date())
    }

    private var label: String {
        var text = TimestampPill.dateFormatter.string(from: timestamp.date() ?? Date())
        if timestamp.hasTime {
            text += String(format: " %02d:%02d", timestamp.startHour ?? 0, timestamp.startMinute ?? 0)
        }
        if let repeater = timestamp.repeater {
            text += " " + repeater.text
        }
        return text
    }

    private var kindLabel: String {
        switch kind {
        case .scheduled: return "Scheduled"
        case .deadline: return isOverdue ? "Overdue deadline" : "Deadline"
        case .closed: return "Closed"
        case .plain: return "Date"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

// MARK: - Content blocks

struct OrgContentBlocksView: View {
    let content: [OrgContent]
    /// `(contentIndex, itemPath)` — the index of the list element in `content`
    /// and the item path within that list.
    let toggle: (Int, [Int]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(content.enumerated()), id: \.offset) { index, element in
                elementView(element, index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func elementView(_ element: OrgContent, index: Int) -> some View {
        switch element {
        case .blank, .keyword:
            EmptyView()
        case .paragraph(let paragraph):
            Text(OrgInlineRenderer.attributed(paragraph.inlines))
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .list(let list):
            OrgListView(list: list, contentIndex: index, toggle: toggle)
        case .table(let table):
            OrgTableView(table: table)
        case .block(let block):
            OrgBlockView(block: block)
        case .horizontalRule:
            Divider().padding(.vertical, 2)
        case .comment(let lines):
            Text(lines.joined(separator: "\n"))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .drawer:
            EmptyView()
        case .footnoteDefinition(let footnote):
            Text(footnote.lines.joined(separator: "\n"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .raw(let string):
            if !string.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(string).font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyView()
            }
        }
    }

    /// Whether `content` contains anything the reader draws (used to decide
    /// whether a headline shows a disclosure chevron).
    static func hasVisible(_ content: [OrgContent]) -> Bool {
        content.contains { element in
            switch element {
            case .blank, .keyword, .drawer: return false
            case .raw(let s): return !s.trimmingCharacters(in: .whitespaces).isEmpty
            default: return true
            }
        }
    }
}

// MARK: - Lists

struct OrgListView: View {
    let list: OrgList
    let contentIndex: Int
    let toggle: (Int, [Int]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                OrgListItemRow(item: item, path: [index], contentIndex: contentIndex, toggle: toggle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OrgListItemRow: View {
    let item: OrgListItem
    let path: [Int]
    let contentIndex: Int
    let toggle: (Int, [Int]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                marker
                Text(OrgInlineRenderer.attributed(item.inlines))
                    .font(.body)
                    .strikethrough(item.checkbox == .checked)
                    .foregroundStyle(item.checkbox == .checked ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !item.trailing.isEmpty {
                let text = item.trailing
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: "\n")
                if !text.isEmpty {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(Array(item.children.enumerated()), id: \.offset) { index, child in
                OrgListItemRow(item: child, path: path + [index],
                               contentIndex: contentIndex, toggle: toggle)
                    .padding(.leading, 18)
            }
        }
    }

    @ViewBuilder private var marker: some View {
        if let checkbox = item.checkbox {
            Button { toggle(contentIndex, path) } label: {
                Image(systemName: checkboxSymbol(checkbox))
                    .foregroundStyle(checkbox == .checked ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(checkbox == .checked ? "Mark \(OrgInlineRenderer.plainText(item.inlines)) incomplete" : "Mark \(OrgInlineRenderer.plainText(item.inlines)) complete")
            .accessibilityValue(checkbox == .checked ? "Completed" : checkbox == .partial ? "Partially completed" : "Not completed")
            .accessibilityHint("Toggles this checklist item.")
        } else if item.isOrdered {
            Text(item.bullet)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text("•")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func checkboxSymbol(_ checkbox: OrgCheckbox) -> String {
        switch checkbox {
        case .checked: return "checkmark.square.fill"
        case .partial: return "minus.square"
        case .unchecked: return "square"
        }
    }
}

// MARK: - Tables

struct OrgTableView: View {
    let table: OrgTable

    var body: some View {
        let rows = table.rows.filter { !$0.isSeparator }
        let columnCount = rows.map(\.cells.count).max() ?? 0
        let hasHeader = table.rows.contains { $0.isSeparator }

        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(0..<columnCount), id: \.self) { column in
                            Text(column < row.cells.count ? row.cells[column] : "")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(hasHeader && rowIndex == 0 ? .semibold : .regular)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table with \(rows.count) rows and \(columnCount) columns")
        .accessibilityHint("Swipe left or right to view all columns.")
    }
}

// MARK: - Blocks

struct OrgBlockView: View {
    let block: OrgBlock

    private var isMonospaced: Bool { block.type == "SRC" || block.type == "EXAMPLE" }
    private var isQuote: Bool { block.type == "QUOTE" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if block.type == "SRC", let language = block.language {
                Text(language.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(block.lines.joined(separator: "\n"))
                .font(isMonospaced ? .system(.callout, design: .monospaced) : .body)
                .italic(isQuote)
                .foregroundStyle(isQuote ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if isQuote {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(blockAccessibilityLabel)
    }

    private var blockAccessibilityLabel: String {
        let type = block.type.lowercased()
        if let language = block.language, !language.isEmpty {
            return "\(type) block, \(language). \(block.lines.joined(separator: " "))"
        }
        return "\(type) block. \(block.lines.joined(separator: " "))"
    }
}
