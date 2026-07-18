//
//  OrgParser.swift
//  OrgSync
//
//  Hand-written recursive org-mode parser. Splits a document into a preamble
//  and a headline tree, parses planning lines, property drawers, and section
//  body content (paragraphs, lists, tables, blocks, drawers, comments, rules,
//  keyword lines, footnote definitions). Unrecognized lines are preserved
//  verbatim as `.raw` content so serialization is lossless.
//

import Foundation

public enum OrgParser {
    public static func parse(_ text: String) -> OrgDocument {
        let lines = text.components(separatedBy: "\n")
        let config = scanTodoConfig(lines)

        // Split into preamble + flat headline sections.
        var preambleLines: [String] = []
        var flat: [(level: Int, heading: String, body: [String])] = []
        var current: (level: Int, heading: String, body: [String])?

        for line in lines {
            if let level = headlineLevel(line) {
                if let c = current { flat.append(c) }
                current = (level, line, [])
            } else if current != nil {
                current!.body.append(line)
            } else {
                preambleLines.append(line)
            }
        }
        if let c = current { flat.append(c) }

        let preamble = parseContent(preambleLines)
        let parsed = flat.map { parseHeadline(level: $0.level, heading: $0.heading, body: $0.body, config: config) }
        let tree = buildTree(parsed)

        return OrgDocument(preamble: preamble, headlines: tree, todoConfig: config)
    }

    // MARK: - TODO config scan

    private static func scanTodoConfig(_ lines: [String]) -> OrgTodoConfig {
        var kws: [(key: String, value: String)] = []
        for line in lines {
            let t = line.drop(while: { $0 == " " || $0 == "\t" })
            guard t.hasPrefix("#+") else { continue }
            guard let (key, value) = keywordParts(String(t.dropFirst(2))) else { continue }
            if OrgTodoConfig.keywordNames.contains(key.uppercased()) {
                kws.append((key, value))
            }
        }
        return OrgTodoConfig.from(keywords: kws)
    }

    // MARK: - Headlines

    /// Returns the star count if `line` is a headline, else nil.
    static func headlineLevel(_ line: String) -> Int? {
        var count = 0
        for ch in line {
            if ch == "*" { count += 1 } else { break }
        }
        guard count > 0 else { return nil }
        let after = line.index(line.startIndex, offsetBy: count)
        if after == line.endIndex { return count }          // "***"
        let next = line[after]
        return (next == " " || next == "\t") ? count : nil  // "*** title"
    }

    private static func parseHeadline(level: Int, heading: String, body rawBody: [String],
                                      config: OrgTodoConfig) -> OrgHeadline {
        // Heading line components.
        let afterStars = String(heading.dropFirst(level))
        var content = Substring(afterStars).drop(while: { $0 == " " || $0 == "\t" })

        var todo: String?
        // TODO keyword: the first whitespace-delimited word, if configured.
        if let sp = content.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            let word = String(content[content.startIndex..<sp])
            if config.isKeyword(word) {
                todo = word
                content = content[sp...].drop(while: { $0 == " " || $0 == "\t" })
            }
        } else if config.isKeyword(String(content)) {
            todo = String(content)
            content = content[content.endIndex...]
        }

        var priority: Character?
        if content.hasPrefix("[#"), content.count >= 4 {
            let arr = Array(content)
            if arr[3] == "]" {
                priority = arr[2]
                content = content.dropFirst(4).drop(while: { $0 == " " || $0 == "\t" })
            }
        }

        let (title, tags) = extractTags(String(content))

        // Body: planning line, property drawer, then content.
        var idx = 0
        var planning = OrgPlanning()
        if idx < rawBody.count, let p = parsePlanning(rawBody[idx]) {
            planning = p
            idx += 1
        }
        var propDrawer: OrgPropertyDrawer?
        if idx < rawBody.count, let (drawer, consumed) = parsePropertyDrawer(rawBody, idx) {
            propDrawer = drawer
            idx += consumed
        }
        // Planning can also follow a property drawer in some files.
        if planning.isEmpty, idx < rawBody.count, let p = parsePlanning(rawBody[idx]) {
            planning = p
            idx += 1
        }

        let bodyContent = parseContent(Array(rawBody[idx...]))
        return OrgHeadline(level: level, todoKeyword: todo, priority: priority,
                           title: title, tags: tags, planning: planning,
                           propertyDrawer: propDrawer, body: bodyContent,
                           children: [], raw: heading)
    }

    private static func buildTree(_ flat: [OrgHeadline]) -> [OrgHeadline] {
        var index = 0
        func build(minLevel: Int) -> [OrgHeadline] {
            var nodes: [OrgHeadline] = []
            while index < flat.count {
                let headline = flat[index]
                if headline.level < minLevel { break }
                index += 1
                var node = headline
                node.children = build(minLevel: headline.level + 1)
                nodes.append(node)
            }
            return nodes
        }
        return build(minLevel: 1)
    }

    static func extractTags(_ s: String) -> (String, [String]) {
        guard s.hasSuffix(":") else { return (rtrim(s), []) }
        let chars = Array(s)
        var j = chars.count - 1
        while j >= 0, isTagChar(chars[j]) || chars[j] == ":" { j -= 1 }
        // Need whitespace (or start) before the tag block.
        let precededOK = (j < 0) || chars[j] == " " || chars[j] == "\t"
        guard precededOK else { return (rtrim(s), []) }
        let block = String(chars[(j + 1)...])
        guard block.hasPrefix(":"), block.hasSuffix(":"), block.count > 1 else { return (rtrim(s), []) }
        let names = block.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        guard !names.isEmpty, names.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isTagChar) }) else {
            return (rtrim(s), [])
        }
        let titlePart = j < 0 ? "" : String(chars[0..<j])
        return (rtrim(titlePart), names)
    }

    nonisolated static func isTagChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "@" || c == "#" || c == "%"
    }

    private static func rtrim(_ s: String) -> String {
        var end = s.endIndex
        while end > s.startIndex {
            let prev = s.index(before: end)
            if s[prev] == " " || s[prev] == "\t" { end = prev } else { break }
        }
        return String(s[s.startIndex..<end])
    }

    // MARK: - Planning

    static func parsePlanning(_ line: String) -> OrgPlanning? {
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        var s = Substring(line.dropFirst(indent.count))
        let keywords = ["SCHEDULED:", "DEADLINE:", "CLOSED:"]
        guard keywords.contains(where: { s.hasPrefix($0) }) else { return nil }

        var planning = OrgPlanning(indent: indent, raw: line)
        while true {
            s = s.drop(while: { $0 == " " || $0 == "\t" })
            var matched: String?
            for kw in keywords where s.hasPrefix(kw) { matched = kw; break }
            guard let kw = matched else { break }
            s = s.dropFirst(kw.count).drop(while: { $0 == " " || $0 == "\t" })
            guard let (ts, len) = OrgTimestamp.parsePrefix(s) else { return nil }
            s = s.dropFirst(len)
            switch kw {
            case "SCHEDULED:": planning.scheduled = ts
            case "DEADLINE:": planning.deadline = ts
            case "CLOSED:": planning.closed = ts
            default: break
            }
        }
        // Trailing non-whitespace means this wasn't a clean planning line.
        guard s.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        return planning.isEmpty ? nil : planning
    }

    // MARK: - Property drawer

    private static func parsePropertyDrawer(_ lines: [String], _ start: Int) -> (OrgPropertyDrawer, Int)? {
        let first = lines[start]
        let indent = String(first.prefix(while: { $0 == " " || $0 == "\t" }))
        guard first.dropFirst(indent.count).uppercased().hasPrefix(":PROPERTIES:") else { return nil }
        var props: [OrgProperty] = []
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.uppercased().hasPrefix(":END:") {
                let drawer = OrgPropertyDrawer(properties: props, indent: indent,
                                               beginRaw: first, endRaw: line)
                return (drawer, i - start + 1)
            }
            if trimmed.hasPrefix(":"), let colon = trimmed.dropFirst().firstIndex(of: ":") {
                let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<colon])
                let value = String(trimmed[trimmed.index(after: colon)...])
                    .drop(while: { $0 == " " || $0 == "\t" })
                props.append(OrgProperty(key: key, value: String(value), raw: line))
            } else {
                props.append(OrgProperty(key: "", value: "", raw: line))
            }
            i += 1
        }
        return nil // no :END: — not a valid drawer
    }

    // MARK: - Content

    static func parseContent(_ lines: [String]) -> [OrgContent] {
        var result: [OrgContent] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]

            if line.isEmpty { result.append(.blank); i += 1; continue }
            if line.allSatisfy({ $0 == " " || $0 == "\t" }) { result.append(.raw(line)); i += 1; continue }

            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

            // Comments: `#` alone or `# ...`
            if line.first == "#", isCommentLine(line) {
                var block = [line]; i += 1
                while i < lines.count, isCommentLine(lines[i]) { block.append(lines[i]); i += 1 }
                result.append(.comment(block)); continue
            }

            // Keyword lines & blocks
            if trimmed.hasPrefix("#+") {
                let rest = trimmed.dropFirst(2)
                if rest.uppercased().hasPrefix("BEGIN_"), let (block, consumed) = parseBlock(lines, i) {
                    result.append(.block(block)); i += consumed; continue
                }
                if let (key, value) = keywordParts(String(rest)) {
                    result.append(.keyword(OrgKeyword(key: key, value: value, raw: line)))
                    i += 1; continue
                }
            }

            // Horizontal rule
            if isHorizontalRule(line) { result.append(.horizontalRule(line)); i += 1; continue }

            // Footnote definition
            if line.hasPrefix("[fn:"), let close = line.firstIndex(of: "]") {
                let label = String(line[line.index(line.startIndex, offsetBy: 4)..<close])
                var block = [line]; i += 1
                while i < lines.count, !lines[i].isEmpty, headlineLevel(lines[i]) == nil,
                      !lines[i].hasPrefix("[fn:") {
                    block.append(lines[i]); i += 1
                }
                result.append(.footnoteDefinition(OrgFootnoteDefinition(label: label, lines: block)))
                continue
            }

            // Table
            if trimmed.first == "|" {
                var rows: [OrgTableRow] = []
                while i < lines.count, lines[i].drop(while: { $0 == " " || $0 == "\t" }).first == "|" {
                    rows.append(parseTableRow(lines[i])); i += 1
                }
                result.append(.table(OrgTable(rows: rows))); continue
            }

            // Generic drawer (`:NAME:` ... `:END:`)
            if let (drawer, consumed) = parseDrawer(lines, i) {
                result.append(.drawer(drawer)); i += consumed; continue
            }

            // List
            if isListLine(line) {
                let (list, consumed) = parseList(lines, i)
                result.append(.list(list)); i += consumed; continue
            }

            // Paragraph
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                if l.isEmpty || startsNewConstruct(l) { break }
                para.append(l); i += 1
            }
            if para.isEmpty { result.append(.raw(line)); i += 1 }
            else { result.append(.paragraph(OrgParagraph(lines: para))) }
        }
        return result
    }

    private static func startsNewConstruct(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        if trimmed.hasPrefix("#+") { return true }
        if line.first == "#", isCommentLine(line) { return true }
        if trimmed.first == "|" { return true }
        if isHorizontalRule(line) { return true }
        if isListLine(line) { return true }
        if line.hasPrefix("[fn:") { return true }
        if line.allSatisfy({ $0 == " " || $0 == "\t" }) && !line.isEmpty { return true }
        if isDrawerStart(line) { return true }
        return false
    }

    private static func isCommentLine(_ line: String) -> Bool {
        // `#` at column 0 followed by whitespace or end-of-line.
        guard line.first == "#" else { return false }
        if line == "#" { return true }
        let second = line[line.index(after: line.startIndex)]
        return second == " " || second == "\t"
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let t = line.drop(while: { $0 == " " || $0 == "\t" })
        return t.count >= 5 && t.allSatisfy { $0 == "-" }
    }

    private static func parseTableRow(_ line: String) -> OrgTableRow {
        let indentCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let body = line.dropFirst(indentCount)
        // Separator rows look like |---+---| (dashes, plus, pipe only).
        let inner = body.dropFirst().drop(while: { $0 == " " })
        let isSep = inner.first == "-"
        if isSep {
            return OrgTableRow(isSeparator: true, cells: [], raw: line)
        }
        var cells = body.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        // Drop the empty leading cell (before first `|`) and trailing cell (after last `|`).
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return OrgTableRow(isSeparator: false, cells: cells, raw: line)
    }

    private static func parseBlock(_ lines: [String], _ start: Int) -> (OrgBlock, Int)? {
        let first = lines[start]
        let indent = first.prefix(while: { $0 == " " || $0 == "\t" }).count
        let afterHash = first.dropFirst(indent + 2) // skip indent + "#+"
        guard afterHash.uppercased().hasPrefix("BEGIN_") else { return nil }
        let afterBegin = afterHash.dropFirst(6)
        let typeToken = afterBegin.prefix(while: { $0 != " " && $0 != "\t" })
        let type = typeToken.uppercased()
        let parameters = String(afterBegin.dropFirst(typeToken.count)).drop(while: { $0 == " " || $0 == "\t" })
        let endToken = "END_" + type

        var content: [String] = []
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            let t = line.drop(while: { $0 == " " || $0 == "\t" })
            if t.uppercased().hasPrefix("#+" + endToken) {
                let block = OrgBlock(type: type, parameters: String(parameters), lines: content,
                                     beginRaw: first, endRaw: line)
                return (block, i - start + 1)
            }
            content.append(line); i += 1
        }
        return nil // unterminated block — treat lines individually
    }

    private static func isDrawerStart(_ line: String) -> Bool {
        let t = line.drop(while: { $0 == " " || $0 == "\t" })
        guard t.first == ":", t.count >= 2 else { return false }
        let name = t.dropFirst().prefix(while: { $0 != ":" })
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return false }
        let afterName = t.dropFirst(1 + name.count)
        guard afterName.first == ":" else { return false }
        let rest = afterName.dropFirst()
        guard rest.allSatisfy({ $0 == " " || $0 == "\t" }) else { return false }
        let upper = name.uppercased()
        return upper != "END" && upper != "PROPERTIES"
    }

    private static func parseDrawer(_ lines: [String], _ start: Int) -> (OrgDrawer, Int)? {
        guard isDrawerStart(lines[start]) else { return nil }
        let first = lines[start]
        let t = first.drop(while: { $0 == " " || $0 == "\t" })
        let name = String(t.dropFirst().prefix(while: { $0 != ":" }))
        var content: [String] = []
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            let lt = line.drop(while: { $0 == " " || $0 == "\t" })
            if lt.uppercased().hasPrefix(":END:") {
                return (OrgDrawer(name: name, lines: content, beginRaw: first, endRaw: line), i - start + 1)
            }
            if headlineLevel(line) != nil { break }
            content.append(line); i += 1
        }
        return nil // unterminated
    }

    // MARK: - Lists

    static func isListLine(_ line: String) -> Bool {
        parseBullet(line) != nil
    }

    /// Returns (indentWidth, bullet, textAfterBullet) if `line` is a bullet line.
    private static func parseBullet(_ line: String) -> (Int, String, String)? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
        let indentCount = indent.count
        let after = line.dropFirst(indentCount)
        guard let first = after.first else { return nil }

        if first == "-" || first == "+" || (first == "*" && indentCount > 0) {
            let rest = after.dropFirst()
            if rest.isEmpty { return (indentCount, String(first), "") }
            guard rest.first == " " || rest.first == "\t" else { return nil }
            let text = rest.drop(while: { $0 == " " || $0 == "\t" })
            return (indentCount, String(first), String(text))
        }
        // Ordered: digits then . or )
        if first.isNumber {
            let digits = after.prefix(while: { $0.isNumber })
            let afterDigits = after.dropFirst(digits.count)
            guard let delim = afterDigits.first, delim == "." || delim == ")" else { return nil }
            let rest = afterDigits.dropFirst()
            if rest.isEmpty { return (indentCount, "\(digits)\(delim)", "") }
            guard rest.first == " " || rest.first == "\t" else { return nil }
            let text = rest.drop(while: { $0 == " " || $0 == "\t" })
            return (indentCount, "\(digits)\(delim)", String(text))
        }
        return nil
    }

    private static func indentWidth(_ line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).count
    }

    private static func parseList(_ lines: [String], _ start: Int) -> (OrgList, Int) {
        let base = indentWidth(lines[start])
        var block: [String] = []
        var i = start
        while i < lines.count {
            let line = lines[i]
            if line.isEmpty { break }
            if indentWidth(line) < base { break }
            if indentWidth(line) == base && parseBullet(line) == nil { break }
            block.append(line); i += 1
        }
        let items = buildListItems(block)
        return (OrgList(items: items), block.count)
    }

    private static func buildListItems(_ block: [String]) -> [OrgListItem] {
        var items: [OrgListItem] = []
        var idx = 0
        while idx < block.count {
            let line = block[idx]
            guard let (ind, bullet, textRaw) = parseBullet(line) else { idx += 1; continue }
            let indentStr = String(line.prefix(ind))

            // Checkbox
            var checkbox: OrgCheckbox?
            var text = textRaw
            if let (cb, remainder) = leadingCheckbox(textRaw) {
                checkbox = cb; text = remainder
            }

            var item = OrgListItem(indent: indentStr, bullet: bullet, checkbox: checkbox,
                                   text: text, raw: line)
            idx += 1

            // Gather deeper-indented lines belonging to this item.
            var childLines: [String] = []
            while idx < block.count, indentWidth(block[idx]) > ind {
                childLines.append(block[idx]); idx += 1
            }
            var t = 0
            while t < childLines.count, parseBullet(childLines[t]) == nil {
                item.trailing.append(childLines[t]); t += 1
            }
            if t < childLines.count {
                item.children = buildListItems(Array(childLines[t...]))
            }
            items.append(item)
        }
        return items
    }

    private static func leadingCheckbox(_ s: String) -> (OrgCheckbox, String)? {
        let candidates: [(String, OrgCheckbox)] = [("[ ]", .unchecked), ("[X]", .checked),
                                                    ("[x]", .checked), ("[-]", .partial)]
        for (marker, cb) in candidates where s.hasPrefix(marker) {
            let rest = s.dropFirst(marker.count)
            if rest.isEmpty { return (cb, "") }
            if rest.first == " " || rest.first == "\t" {
                return (cb, String(rest.drop(while: { $0 == " " || $0 == "\t" })))
            }
        }
        return nil
    }

    // MARK: - Keyword parsing

    /// Splits `KEY: value` (already stripped of the leading `#+`).
    static func keywordParts(_ s: String) -> (String, String)? {
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let key = String(s[s.startIndex..<colon])
        guard !key.isEmpty else { return nil }
        var value = s[s.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        return (key, String(value))
    }
}
