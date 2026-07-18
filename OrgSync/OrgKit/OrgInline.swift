//
//  OrgInline.swift
//  OrgSync
//
//  Inline markup model + parser for org text spans: emphasis (bold, italic,
//  underline, verbatim, code, strikethrough), links `[[target][desc]]` /
//  `[[target]]`, and bare URLs. Emphasis honors org's boundary rules
//  (markers only take effect at word boundaries; the body may not begin or end
//  with whitespace). Verbatim (`=`) and code (`~`) spans are literal — no
//  nested markup inside them.
//

import Foundation

public indirect enum OrgInline: Sendable, Hashable {
    case text(String)
    case bold([OrgInline])
    case italic([OrgInline])
    case underline([OrgInline])
    case strikethrough([OrgInline])
    case verbatim(String)
    case code(String)
    /// `[[target][description]]`; `description` is nil for `[[target]]`.
    case link(target: String, description: String?)
    /// A bare URL such as `https://example.com`.
    case plainLink(String)

    /// Serialize a single inline node back to org text.
    public func serialize() -> String {
        switch self {
        case .text(let s): return s
        case .bold(let c): return "*" + OrgInline.serialize(c) + "*"
        case .italic(let c): return "/" + OrgInline.serialize(c) + "/"
        case .underline(let c): return "_" + OrgInline.serialize(c) + "_"
        case .strikethrough(let c): return "+" + OrgInline.serialize(c) + "+"
        case .verbatim(let s): return "=" + s + "="
        case .code(let s): return "~" + s + "~"
        case .link(let target, let desc):
            if let d = desc { return "[[\(target)][\(d)]]" }
            return "[[\(target)]]"
        case .plainLink(let s): return s
        }
    }

    public static func serialize(_ nodes: [OrgInline]) -> String {
        nodes.map { $0.serialize() }.joined()
    }
}

public enum OrgInlineParser {
    // Org's default `org-emphasis-regexp-components`.
    private static let preAllowed = Set(" \t('\"{")
    private static let postAllowed = Set(" \t-.,:!?;'\")}[")
    private static let markers: [Character: (String) -> OrgInline] = [
        "*": { .bold(OrgInlineParser.parse($0)) },
        "/": { .italic(OrgInlineParser.parse($0)) },
        "_": { .underline(OrgInlineParser.parse($0)) },
        "+": { .strikethrough(OrgInlineParser.parse($0)) },
    ]
    private static let verbatimMarkers: Set<Character> = ["=", "~"]

    public static func parse(_ text: String) -> [OrgInline] {
        let chars = Array(text)
        var result: [OrgInline] = []
        var textBuffer: [Character] = []
        var i = 0

        func flush() {
            if !textBuffer.isEmpty {
                result.append(.text(String(textBuffer)))
                textBuffer.removeAll(keepingCapacity: true)
            }
        }

        while i < chars.count {
            let c = chars[i]

            // Links: [[target]] or [[target][desc]]
            if c == "[", i + 1 < chars.count, chars[i + 1] == "[" {
                if let (node, next) = parseLink(chars, i) {
                    flush()
                    result.append(node)
                    i = next
                    continue
                }
            }

            // Bare URLs
            if c == "h" || c == "m" || c == "f" {
                if let (node, next) = parsePlainLink(chars, i) {
                    flush()
                    result.append(node)
                    i = next
                    continue
                }
            }

            // Emphasis / verbatim / code
            if (markers[c] != nil || verbatimMarkers.contains(c)),
               let (node, next) = parseEmphasis(chars, i) {
                flush()
                result.append(node)
                i = next
                continue
            }

            textBuffer.append(c)
            i += 1
        }
        flush()
        return result
    }

    // MARK: - Emphasis

    private static func parseEmphasis(_ chars: [Character], _ start: Int) -> (OrgInline, Int)? {
        let marker = chars[start]
        // Pre-char rule: BOL or an allowed pre char.
        if start > 0 {
            let pre = chars[start - 1]
            if !preAllowed.contains(pre) { return nil }
        }
        // Body must not start with whitespace, and the marker must be followed
        // by a valid body char (not the marker itself, not whitespace).
        let bodyStart = start + 1
        guard bodyStart < chars.count else { return nil }
        let firstBody = chars[bodyStart]
        if firstBody == " " || firstBody == "\t" { return nil }

        let isVerbatim = verbatimMarkers.contains(marker)

        // Scan for the closing marker.
        var j = bodyStart
        while j < chars.count {
            if chars[j] == marker {
                // The char before the closing marker must be a valid border
                // (non-whitespace) and the char after must be an allowed post char.
                let beforeClose = chars[j - 1]
                if beforeClose == " " || beforeClose == "\t" { j += 1; continue }
                let afterOK: Bool
                if j + 1 >= chars.count {
                    afterOK = true
                } else {
                    afterOK = postAllowed.contains(chars[j + 1])
                }
                if afterOK {
                    let bodyChars = Array(chars[bodyStart..<j])
                    let body = String(bodyChars)
                    let node: OrgInline
                    if isVerbatim {
                        node = marker == "=" ? .verbatim(body) : .code(body)
                    } else {
                        node = markers[marker]!(body)
                    }
                    return (node, j + 1)
                }
            }
            // Emphasis bodies span at most one line in org; stop at newline.
            if chars[j] == "\n", chars[safe: j + 1] == "\n" { return nil }
            j += 1
        }
        return nil
    }

    // MARK: - Links

    private static func parseLink(_ chars: [Character], _ start: Int) -> (OrgInline, Int)? {
        // start points at first '['; expect "[["
        var i = start + 2
        var target: [Character] = []
        while i < chars.count, chars[i] != "]" {
            target.append(chars[i]); i += 1
        }
        guard i < chars.count, chars[i] == "]" else { return nil }
        i += 1 // consume first ']'
        guard i < chars.count else { return nil }

        if chars[i] == "]" {
            // [[target]]
            return (.link(target: String(target), description: nil), i + 1)
        }
        if chars[i] == "[" {
            i += 1
            var desc: [Character] = []
            while i < chars.count, chars[i] != "]" {
                desc.append(chars[i]); i += 1
            }
            guard i + 1 < chars.count, chars[i] == "]", chars[i + 1] == "]" else { return nil }
            return (.link(target: String(target), description: String(desc)), i + 2)
        }
        return nil
    }

    // MARK: - Plain links

    private static let schemes = ["https://", "http://", "mailto:", "ftp://"]

    private static func parsePlainLink(_ chars: [Character], _ start: Int) -> (OrgInline, Int)? {
        let remaining = String(chars[start...])
        for scheme in schemes where remaining.hasPrefix(scheme) {
            var i = start + scheme.count
            while i < chars.count, !isURLTerminator(chars[i]) {
                i += 1
            }
            // Trim trailing punctuation that org excludes from bare links.
            while i > start + scheme.count, ".,;:!?)".contains(chars[i - 1]) {
                i -= 1
            }
            guard i > start + scheme.count else { return nil }
            return (.plainLink(String(chars[start..<i])), i)
        }
        return nil
    }

    private static func isURLTerminator(_ c: Character) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "<" || c == ">" || c == "[" || c == "]"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
