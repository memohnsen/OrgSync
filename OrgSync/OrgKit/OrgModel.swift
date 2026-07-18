//
//  OrgModel.swift
//  OrgSync
//
//  The org document data model: `OrgDocument` (in-buffer keywords, preamble
//  content, and the headline tree), `OrgHeadline`, and the content-element
//  types (paragraphs, lists, tables, blocks, drawers, comments, rules, keyword
//  lines, footnote definitions). All value types.
//
//  Round-trip strategy: constructs that are cheap to reproduce carry an
//  optional `raw` capture set by the parser and used verbatim on serialize;
//  mutation helpers clear `raw` so the element is regenerated canonically.
//

import Foundation

// MARK: - Content elements

public enum OrgCheckbox: String, Sendable, Hashable {
    case unchecked = "[ ]"
    case checked = "[X]"
    case partial = "[-]"
}

/// A block-level piece of section body content.
public indirect enum OrgContent: Sendable, Hashable {
    case blank
    case paragraph(OrgParagraph)
    case list(OrgList)
    case table(OrgTable)
    case block(OrgBlock)
    case drawer(OrgDrawer)
    case comment([String])
    case horizontalRule(String)
    case keyword(OrgKeyword)
    case footnoteDefinition(OrgFootnoteDefinition)
    /// An unrecognized / odd line preserved verbatim.
    case raw(String)
}

public struct OrgParagraph: Sendable, Hashable {
    public var lines: [String]
    public init(lines: [String]) { self.lines = lines }
    public var text: String { lines.joined(separator: "\n") }
    public var inlines: [OrgInline] { OrgInlineParser.parse(text) }
}

public struct OrgKeyword: Sendable, Hashable {
    public var key: String
    public var value: String
    /// Verbatim source line (preserves exact spacing).
    public var raw: String?
    public init(key: String, value: String, raw: String? = nil) {
        self.key = key; self.value = value; self.raw = raw
    }
}

public struct OrgFootnoteDefinition: Sendable, Hashable {
    public var label: String
    public var lines: [String]
    public init(label: String, lines: [String]) { self.label = label; self.lines = lines }
}

// MARK: Lists

public struct OrgListItem: Sendable, Hashable {
    public var indent: String
    public var bullet: String          // "-", "+", "*", "1.", "1)"
    public var checkbox: OrgCheckbox?
    /// Text after the bullet (and checkbox), first line only.
    public var text: String
    /// Further-indented continuation / nested lines, verbatim.
    public var children: [OrgListItem]
    public var trailing: [String]
    public var raw: String?

    public init(indent: String, bullet: String, checkbox: OrgCheckbox?, text: String,
                children: [OrgListItem] = [], trailing: [String] = [], raw: String? = nil) {
        self.indent = indent; self.bullet = bullet; self.checkbox = checkbox
        self.text = text; self.children = children; self.trailing = trailing; self.raw = raw
    }

    public var isOrdered: Bool { bullet.first?.isNumber ?? false }
    public var inlines: [OrgInline] { OrgInlineParser.parse(text) }
}

public struct OrgList: Sendable, Hashable {
    public var items: [OrgListItem]
    public init(items: [OrgListItem]) { self.items = items }
}

// MARK: Tables

public struct OrgTableRow: Sendable, Hashable {
    public var isSeparator: Bool
    public var cells: [String]
    public var raw: String?
    public init(isSeparator: Bool, cells: [String], raw: String? = nil) {
        self.isSeparator = isSeparator; self.cells = cells; self.raw = raw
    }
}

public struct OrgTable: Sendable, Hashable {
    public var rows: [OrgTableRow]
    public init(rows: [OrgTableRow]) { self.rows = rows }
}

// MARK: Blocks & drawers

public struct OrgBlock: Sendable, Hashable {
    /// Block type, uppercased: SRC, QUOTE, EXAMPLE, VERSE, CENTER, ...
    public var type: String
    /// Parameters after the type on the `#+BEGIN_` line (e.g. a src language).
    public var parameters: String
    public var lines: [String]
    /// Verbatim begin/end lines to reproduce exact casing/spacing.
    public var beginRaw: String?
    public var endRaw: String?

    public init(type: String, parameters: String, lines: [String],
                beginRaw: String? = nil, endRaw: String? = nil) {
        self.type = type; self.parameters = parameters; self.lines = lines
        self.beginRaw = beginRaw; self.endRaw = endRaw
    }

    /// For SRC blocks, the language is the first parameters token.
    public var language: String? {
        guard type == "SRC" else { return nil }
        let t = parameters.split(separator: " ", maxSplits: 1).first.map(String.init)
        return (t?.isEmpty ?? true) ? nil : t
    }
}

public struct OrgDrawer: Sendable, Hashable {
    public var name: String
    public var lines: [String]
    public var beginRaw: String?
    public var endRaw: String?
    public init(name: String, lines: [String], beginRaw: String? = nil, endRaw: String? = nil) {
        self.name = name; self.lines = lines; self.beginRaw = beginRaw; self.endRaw = endRaw
    }
}

// MARK: - Planning & properties

public struct OrgPlanning: Sendable, Hashable {
    public var scheduled: OrgTimestamp?
    public var deadline: OrgTimestamp?
    public var closed: OrgTimestamp?
    /// Leading whitespace of the planning line, preserved for round-trip.
    public var indent: String
    public var raw: String?

    public init(scheduled: OrgTimestamp? = nil, deadline: OrgTimestamp? = nil,
                closed: OrgTimestamp? = nil, indent: String = "", raw: String? = nil) {
        self.scheduled = scheduled; self.deadline = deadline; self.closed = closed
        self.indent = indent; self.raw = raw
    }

    public var isEmpty: Bool { scheduled == nil && deadline == nil && closed == nil }
}

public struct OrgProperty: Sendable, Hashable {
    public var key: String
    public var value: String
    public var raw: String?
    public init(key: String, value: String, raw: String? = nil) {
        self.key = key; self.value = value; self.raw = raw
    }
}

public struct OrgPropertyDrawer: Sendable, Hashable {
    public var properties: [OrgProperty]
    public var indent: String
    public var beginRaw: String?
    public var endRaw: String?
    public init(properties: [OrgProperty], indent: String = "",
                beginRaw: String? = nil, endRaw: String? = nil) {
        self.properties = properties; self.indent = indent
        self.beginRaw = beginRaw; self.endRaw = endRaw
    }
}

// MARK: - Headline

public struct OrgHeadline: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var level: Int
    public var todoKeyword: String?
    public var priority: Character?
    public var title: String
    public var tags: [String]
    public var planning: OrgPlanning
    public var propertyDrawer: OrgPropertyDrawer?
    public var body: [OrgContent]
    public var children: [OrgHeadline]
    /// Verbatim heading line (`*** TODO [#A] Title  :tag:`); used unless mutated.
    public var raw: String?

    public init(level: Int, todoKeyword: String? = nil, priority: Character? = nil,
                title: String, tags: [String] = [],
                planning: OrgPlanning = OrgPlanning(),
                propertyDrawer: OrgPropertyDrawer? = nil,
                body: [OrgContent] = [], children: [OrgHeadline] = [],
                raw: String? = nil) {
        self.level = level; self.todoKeyword = todoKeyword; self.priority = priority
        self.title = title; self.tags = tags; self.planning = planning
        self.propertyDrawer = propertyDrawer; self.body = body
        self.children = children; self.raw = raw
    }

    public var titleInlines: [OrgInline] { OrgInlineParser.parse(title) }

    /// A persistent org-mode `:ID:` property, when present. Unlike a title
    /// path, this survives a heading rename or a move within its file.
    public var persistentID: String? {
        propertyDrawer?.properties.first { $0.key.uppercased() == "ID" }?.value
    }

    public static func == (lhs: OrgHeadline, rhs: OrgHeadline) -> Bool {
        lhs.level == rhs.level && lhs.todoKeyword == rhs.todoKeyword
            && lhs.priority == rhs.priority && lhs.title == rhs.title
            && lhs.tags == rhs.tags && lhs.planning == rhs.planning
            && lhs.propertyDrawer == rhs.propertyDrawer && lhs.body == rhs.body
            && lhs.children == rhs.children && lhs.raw == rhs.raw
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(level); hasher.combine(title); hasher.combine(todoKeyword)
    }
}

// MARK: - Document

public struct OrgDocument: Sendable {
    /// Content appearing before the first headline (includes keyword lines).
    public var preamble: [OrgContent]
    public var headlines: [OrgHeadline]
    public var todoConfig: OrgTodoConfig

    public init(preamble: [OrgContent] = [], headlines: [OrgHeadline] = [],
                todoConfig: OrgTodoConfig = .default) {
        self.preamble = preamble
        self.headlines = headlines
        self.todoConfig = todoConfig
    }

    /// In-buffer keywords found in the preamble (`#+KEY: value`).
    public var keywords: [OrgKeyword] {
        preamble.compactMap { if case .keyword(let k) = $0 { return k } else { return nil } }
    }

    /// `#+TITLE:` value, if present.
    public var title: String? {
        keywords.first { $0.key.uppercased() == "TITLE" }?.value
    }
}

// MARK: - Outline identifier

/// A stable, file-relative address for a heading, used by later phases
/// (agenda, reminders sync) to refer to a heading across edits.
public struct OrgOutline: Sendable, Hashable, Codable {
    /// Repo-relative file path (e.g. `notes/work.org`).
    public var filePath: String
    /// Titles from the root headline down to the target (outline path).
    public var headingPath: [String]
    /// Sibling index among headings sharing this path (disambiguates duplicates).
    public var index: Int

    public init(filePath: String, headingPath: [String], index: Int = 0) {
        self.filePath = filePath
        self.headingPath = headingPath
        self.index = index
    }
}

/// A TODO headline surfaced by document queries, with its outline address.
public struct OrgTodoItem: Sendable, Hashable, Identifiable {
    public var outline: OrgOutline
    public var keyword: String
    public var isDone: Bool
    public var priority: Character?
    public var title: String
    public var tags: [String]
    public var scheduled: OrgTimestamp?
    public var deadline: OrgTimestamp?
    public var persistentID: String?

    public var id: OrgOutline { outline }

    public init(outline: OrgOutline, keyword: String, isDone: Bool, priority: Character?,
                title: String, tags: [String], scheduled: OrgTimestamp?, deadline: OrgTimestamp?,
                persistentID: String? = nil) {
        self.outline = outline; self.keyword = keyword; self.isDone = isDone
        self.priority = priority; self.title = title; self.tags = tags
        self.scheduled = scheduled; self.deadline = deadline
        self.persistentID = persistentID
    }
}
