//
//  OrgInlineRenderer.swift
//  OrgSync
//
//  Renders a parsed inline stream (`[OrgInline]`) into a SwiftUI `AttributedString`
//  for display in the rendered note view. Emphasis maps to inline presentation
//  intents (bold/italic/strikethrough/code), underline to a line style, links to
//  tappable URLs (http/https/mailto/ftp only; org-internal links are inert), and
//  embedded timestamps inside literal text are given a distinct accent style.
//

import SwiftUI

enum OrgInlineRenderer {
    private struct Style {
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        var mono = false
        var secondary = false
        var link: URL?
    }

    /// Build a display `AttributedString` from an inline stream.
    static func attributed(_ inlines: [OrgInline]) -> AttributedString {
        var out = AttributedString()
        for node in inlines { append(node, style: Style(), into: &out) }
        return out
    }

    /// A spoken/plain-text representation for controls that render inline org
    /// markup but require a meaningful accessibility label.
    static func plainText(_ inlines: [OrgInline]) -> String {
        inlines.map(plainText).joined()
    }

    private static func plainText(_ inline: OrgInline) -> String {
        switch inline {
        case .text(let value), .verbatim(let value), .code(let value), .plainLink(let value):
            return value
        case .link(let target, let description):
            return description ?? target
        case .bold(let children), .italic(let children), .underline(let children), .strikethrough(let children):
            return plainText(children)
        }
    }

    private static func append(_ node: OrgInline, style: Style, into out: inout AttributedString) {
        switch node {
        case .text(let s):
            appendText(s, style: style, into: &out)
        case .bold(let children):
            var st = style; st.bold = true
            children.forEach { append($0, style: st, into: &out) }
        case .italic(let children):
            var st = style; st.italic = true
            children.forEach { append($0, style: st, into: &out) }
        case .underline(let children):
            var st = style; st.underline = true
            children.forEach { append($0, style: st, into: &out) }
        case .strikethrough(let children):
            var st = style; st.strike = true
            children.forEach { append($0, style: st, into: &out) }
        case .verbatim(let s):
            var st = style; st.mono = true; st.secondary = true
            appendText(s, style: st, into: &out)
        case .code(let s):
            var st = style; st.mono = true
            appendText(s, style: st, into: &out)
        case .link(let target, let desc):
            var st = style; st.link = validURL(target)
            appendText(desc ?? target, style: st, into: &out)
        case .plainLink(let s):
            var st = style; st.link = validURL(s)
            appendText(s, style: st, into: &out)
        }
    }

    private static func appendText(_ text: String, style: Style, into out: inout AttributedString) {
        for segment in TimestampSplitter.split(text) {
            var run = AttributedString(segment.text)
            var intent: InlinePresentationIntent = []
            if style.bold { intent.insert(.stronglyEmphasized) }
            if style.italic { intent.insert(.emphasized) }
            if style.strike { intent.insert(.strikethrough) }
            if style.mono || segment.isTimestamp { intent.insert(.code) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            if style.underline { run.underlineStyle = Text.LineStyle.single }
            if let link = style.link {
                run.link = link
                run.foregroundColor = .accentColor
            } else if segment.isTimestamp {
                run.foregroundColor = .accentColor
            } else if style.secondary {
                run.foregroundColor = .secondary
            }
            out.append(run)
        }
    }

    private static func validURL(_ target: String) -> URL? {
        let lower = target.lowercased()
        let schemes = ["https://", "http://", "mailto:", "ftp://"]
        guard schemes.contains(where: { lower.hasPrefix($0) }) else { return nil }
        return URL(string: target)
    }
}

/// Splits literal text into alternating plain / timestamp segments so embedded
/// `<...>` and `[...]` timestamps can be styled distinctly.
private enum TimestampSplitter {
    struct Segment { var text: String; var isTimestamp: Bool }

    static func split(_ text: String) -> [Segment] {
        let chars = Array(text)
        var segments: [Segment] = []
        var buffer: [Character] = []
        var i = 0

        func flushPlain() {
            if !buffer.isEmpty {
                segments.append(Segment(text: String(buffer), isTimestamp: false))
                buffer.removeAll(keepingCapacity: true)
            }
        }

        while i < chars.count {
            let c = chars[i]
            if c == "<" || c == "[" {
                let sub = Substring(String(chars[i...]))
                if let (_, len) = OrgTimestamp.parsePrefix(sub) {
                    flushPlain()
                    let end = min(i + len, chars.count)
                    segments.append(Segment(text: String(chars[i..<end]), isTimestamp: true))
                    i = end
                    continue
                }
            }
            buffer.append(c)
            i += 1
        }
        flushPlain()
        return segments.isEmpty ? [Segment(text: text, isTimestamp: false)] : segments
    }
}
