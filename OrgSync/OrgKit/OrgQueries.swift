//
//  OrgQueries.swift
//  OrgSync
//
//  Convenience queries over a parsed document: a flat list of all TODO
//  headlines with stable outline addresses, every timestamp in the document,
//  and the document title.
//

import Foundation

extension OrgHeadline {
    public func isDone(config: OrgTodoConfig) -> Bool {
        todoKeyword.map(config.isDone) ?? false
    }

    /// Timestamps directly on this headline (planning + inline in title/body),
    /// excluding children.
    public func ownTimestamps() -> [OrgTimestamp] {
        var result: [OrgTimestamp] = []
        if let s = planning.scheduled { result.append(s) }
        if let d = planning.deadline { result.append(d) }
        if let c = planning.closed { result.append(c) }
        result += OrgTimestampScanner.scan(title)
        result += OrgQueries.timestamps(in: body)
        return result
    }
}

public enum OrgQueries {
    /// All timestamps embedded in a list of content elements.
    static func timestamps(in content: [OrgContent]) -> [OrgTimestamp] {
        var result: [OrgTimestamp] = []
        for element in content {
            switch element {
            case .paragraph(let p):
                result += OrgTimestampScanner.scan(p.text)
            case .list(let l):
                result += listTimestamps(l.items)
            case .table(let t):
                for row in t.rows where !row.isSeparator {
                    for cell in row.cells { result += OrgTimestampScanner.scan(cell) }
                }
            case .drawer(let d):
                for line in d.lines { result += OrgTimestampScanner.scan(line) }
            case .footnoteDefinition(let f):
                for line in f.lines { result += OrgTimestampScanner.scan(line) }
            case .blank, .raw, .comment, .horizontalRule, .keyword, .block:
                break
            }
        }
        return result
    }

    private static func listTimestamps(_ items: [OrgListItem]) -> [OrgTimestamp] {
        var result: [OrgTimestamp] = []
        for item in items {
            result += OrgTimestampScanner.scan(item.text)
            result += listTimestamps(item.children)
        }
        return result
    }
}

extension OrgDocument {
    /// A flat list of every TODO headline (any keyword in the config), each with
    /// a stable outline address.
    public func todoItems(filePath: String) -> [OrgTodoItem] {
        var items: [OrgTodoItem] = []
        var seenPaths: [[String]: Int] = [:]

        func visit(_ headline: OrgHeadline, path: [String]) {
            let here = path + [headline.title]
            if let keyword = headline.todoKeyword, todoConfig.isKeyword(keyword) {
                let index = seenPaths[here, default: 0]
                seenPaths[here] = index + 1
                let outline = OrgOutline(filePath: filePath, headingPath: here, index: index)
                items.append(OrgTodoItem(
                    outline: outline,
                    keyword: keyword,
                    isDone: todoConfig.isDone(keyword),
                    priority: headline.priority,
                    title: headline.title,
                    tags: headline.tags,
                    scheduled: headline.planning.scheduled,
                    deadline: headline.planning.deadline))
            }
            for child in headline.children { visit(child, path: here) }
        }

        for headline in headlines { visit(headline, path: []) }
        return items
    }

    /// The outline address of every headline in the document.
    public func allOutlines(filePath: String) -> [OrgOutline] {
        var result: [OrgOutline] = []
        var seenPaths: [[String]: Int] = [:]
        func visit(_ headline: OrgHeadline, path: [String]) {
            let here = path + [headline.title]
            let index = seenPaths[here, default: 0]
            seenPaths[here] = index + 1
            result.append(OrgOutline(filePath: filePath, headingPath: here, index: index))
            for child in headline.children { visit(child, path: here) }
        }
        for headline in headlines { visit(headline, path: []) }
        return result
    }

    /// Every timestamp in the document (preamble, planning, and inline).
    public func allTimestamps() -> [OrgTimestamp] {
        var result = OrgQueries.timestamps(in: preamble)
        func visit(_ headline: OrgHeadline) {
            result += headline.ownTimestamps()
            for child in headline.children { visit(child) }
        }
        for headline in headlines { visit(headline) }
        return result
    }

    /// Find the headline at a given outline address (ignoring `index`
    /// disambiguation when there is only one match).
    public func headline(at outline: OrgOutline) -> OrgHeadline? {
        var matches = 0
        func visit(_ headline: OrgHeadline, path: [String]) -> OrgHeadline? {
            let here = path + [headline.title]
            if here == outline.headingPath {
                if matches == outline.index { return headline }
                matches += 1
            }
            for child in headline.children {
                if let found = visit(child, path: here) { return found }
            }
            return nil
        }
        for headline in headlines {
            if let found = visit(headline, path: []) { return found }
        }
        return nil
    }
}

/// Scans free text for embedded org timestamps.
enum OrgTimestampScanner {
    static func scan(_ text: String) -> [OrgTimestamp] {
        var result: [OrgTimestamp] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "<" || chars[i] == "[" {
                let sub = Substring(String(chars[i...]))
                if let (ts, len) = OrgTimestamp.parsePrefix(sub) {
                    result.append(ts)
                    i += len
                    continue
                }
            }
            i += 1
        }
        return result
    }
}
