//
//  OrgEditorToolbarConfiguration.swift
//  OrgSync
//
//  The configurable set of insertion commands shown above the keyboard while
//  editing org source. The trailing Edit control is intentionally fixed; only
//  the commands before it are customized.
//

import Foundation

enum OrgEditorCommand: String, CaseIterable, Identifiable {
    case headline
    case todo
    case checkbox
    case timestamp
    case scheduled
    case deadline
    case recurrence
    case priority
    case tag
    case bold
    case italic
    case underline
    case strike
    case code
    case link
    case comment
    case sourceBlock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .headline: "Headline"
        case .todo: "TODO"
        case .checkbox: "Checkbox"
        case .timestamp: "Timestamp"
        case .scheduled: "Scheduled"
        case .deadline: "Deadline"
        case .recurrence: "Repeat weekly"
        case .priority: "Priority"
        case .tag: "Tag"
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strike: "Strike-through"
        case .code: "Code"
        case .link: "Link"
        case .comment: "Comment"
        case .sourceBlock: "Source block"
        }
    }

    var symbol: String {
        switch self {
        case .headline: "text.line.first.and.arrowtriangle.forward"
        case .todo: "checklist.unchecked"
        case .checkbox: "checkmark.square"
        case .timestamp: "calendar"
        case .scheduled: "calendar.badge.clock"
        case .deadline: "calendar.badge.exclamationmark"
        case .recurrence: "arrow.trianglehead.2.clockwise"
        case .priority: "exclamationmark.circle"
        case .tag: "tag"
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strike: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .comment: "text.bubble"
        case .sourceBlock: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum OrgEditorToolbarPreferences {
    private static let commandsKey = "editorToolbar.commands"

    static let defaultCommands: [OrgEditorCommand] = [
        .headline, .todo, .checkbox, .timestamp, .scheduled, .deadline, .recurrence,
        .priority, .tag, .bold, .italic, .underline, .strike, .code, .link,
    ]

    static func load(defaults: UserDefaults = .standard) -> [OrgEditorCommand] {
        let stored = defaults.stringArray(forKey: commandsKey) ?? []
        let commands = uniqueCommands(from: stored.compactMap(OrgEditorCommand.init(rawValue:)))
        guard !commands.isEmpty else { return defaultCommands }
        // Toolbar layouts are persisted, so existing users would otherwise
        // never see commands introduced in a later release. Add recurrence
        // once; it can still be removed from the customization screen.
        return commands.contains(.recurrence) ? commands : commands + [.recurrence]
    }

    static func save(_ commands: [OrgEditorCommand], defaults: UserDefaults = .standard) {
        defaults.set(uniqueCommands(from: commands).map(\.rawValue), forKey: commandsKey)
    }

    static func uniqueCommands(from commands: [OrgEditorCommand]) -> [OrgEditorCommand] {
        var seen = Set<OrgEditorCommand>()
        return commands.filter { seen.insert($0).inserted }
    }
}

struct OrgEditorToolbarPendingInsertion: Equatable {
    let command: OrgEditorCommand
    let range: NSRange
    let expectedText: String
}

enum OrgEditorToolbarInsertionPolicy {
    enum Action: Equatable {
        case none
        case replace
        case remove
    }

    static func pendingInsertion(command: OrgEditorCommand, before: String, after: String) -> OrgEditorToolbarPendingInsertion? {
        let beforeLength = (before as NSString).length
        let afterLength = (after as NSString).length
        guard afterLength > beforeLength else { return nil }

        let beforeNS = before as NSString
        let afterNS = after as NSString
        var prefixLength = 0
        while prefixLength < beforeLength,
              beforeNS.character(at: prefixLength) == afterNS.character(at: prefixLength) {
            prefixLength += 1
        }

        let pending = OrgEditorToolbarPendingInsertion(
            command: command,
            range: NSRange(location: prefixLength, length: afterLength - beforeLength),
            expectedText: after
        )
        return isOnlyContentOnLine(pending, in: after) ? pending : nil
    }

    static func action(pending: OrgEditorToolbarPendingInsertion,
                       with nextCommand: OrgEditorCommand,
                       currentText: String) -> Action {
        guard pending.expectedText == currentText else { return .none }
        return pending.command == nextCommand ? .remove : .replace
    }

    private static func isOnlyContentOnLine(_ pending: OrgEditorToolbarPendingInsertion, in text: String) -> Bool {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: pending.range.location, length: 0))
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        let insertion = nsText.substring(with: pending.range).trimmingCharacters(in: .whitespacesAndNewlines)
        return !insertion.isEmpty && line == insertion
    }
}
