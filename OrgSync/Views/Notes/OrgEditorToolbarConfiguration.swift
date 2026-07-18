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
        .headline, .todo, .checkbox, .timestamp, .scheduled, .deadline,
        .priority, .tag, .bold, .italic, .underline, .strike, .code, .link,
    ]

    static func load(defaults: UserDefaults = .standard) -> [OrgEditorCommand] {
        let stored = defaults.stringArray(forKey: commandsKey) ?? []
        let commands = uniqueCommands(from: stored.compactMap(OrgEditorCommand.init(rawValue:)))
        return commands.isEmpty ? defaultCommands : commands
    }

    static func save(_ commands: [OrgEditorCommand], defaults: UserDefaults = .standard) {
        defaults.set(uniqueCommands(from: commands).map(\.rawValue), forKey: commandsKey)
    }

    static func uniqueCommands(from commands: [OrgEditorCommand]) -> [OrgEditorCommand] {
        var seen = Set<OrgEditorCommand>()
        return commands.filter { seen.insert($0).inserted }
    }
}
