//
//  OrgSerializer.swift
//  OrgSync
//
//  Serializes an `OrgDocument` back to text. Elements that captured a verbatim
//  `raw` on parse are emitted unchanged (guaranteeing lossless round-trips);
//  elements mutated in the model (which clear `raw`) are regenerated in
//  canonical Emacs-org form.
//

import Foundation

extension OrgDocument {
    public func serialize() -> String {
        var lines: [String] = []
        lines += OrgSerializer.contentLines(preamble)
        for h in headlines {
            lines += OrgSerializer.headlineLines(h)
        }
        return lines.joined(separator: "\n")
    }
}

enum OrgSerializer {
    static func headlineLines(_ h: OrgHeadline) -> [String] {
        var lines: [String] = [h.raw ?? regenerateHeading(h)]
        if !h.planning.isEmpty {
            lines.append(planningLine(h.planning))
        }
        if let pd = h.propertyDrawer {
            lines += propertyDrawerLines(pd)
        }
        lines += contentLines(h.body)
        for child in h.children {
            lines += headlineLines(child)
        }
        return lines
    }

    static func regenerateHeading(_ h: OrgHeadline) -> String {
        var parts = String(repeating: "*", count: h.level)
        if let todo = h.todoKeyword { parts += " " + todo }
        if let pri = h.priority { parts += " [#\(pri)]" }
        if !h.title.isEmpty { parts += " " + h.title }
        if !h.tags.isEmpty { parts += " :" + h.tags.joined(separator: ":") + ":" }
        return parts
    }

    static func planningLine(_ p: OrgPlanning) -> String {
        if let raw = p.raw { return raw }
        var parts: [String] = []
        if let c = p.closed { parts.append("CLOSED: " + c.serialize()) }
        if let d = p.deadline { parts.append("DEADLINE: " + d.serialize()) }
        if let s = p.scheduled { parts.append("SCHEDULED: " + s.serialize()) }
        return p.indent + parts.joined(separator: " ")
    }

    static func propertyDrawerLines(_ pd: OrgPropertyDrawer) -> [String] {
        var lines: [String] = [pd.beginRaw ?? (pd.indent + ":PROPERTIES:")]
        for prop in pd.properties {
            if let raw = prop.raw { lines.append(raw) }
            else { lines.append(pd.indent + ":\(prop.key): \(prop.value)") }
        }
        lines.append(pd.endRaw ?? (pd.indent + ":END:"))
        return lines
    }

    static func contentLines(_ content: [OrgContent]) -> [String] {
        var lines: [String] = []
        for element in content {
            switch element {
            case .blank:
                lines.append("")
            case .raw(let s):
                lines.append(s)
            case .paragraph(let p):
                lines += p.lines
            case .comment(let block):
                lines += block
            case .horizontalRule(let s):
                lines.append(s)
            case .keyword(let k):
                lines.append(k.raw ?? "#+\(k.key): \(k.value)")
            case .footnoteDefinition(let f):
                lines += f.lines
            case .table(let t):
                for row in t.rows { lines.append(tableRowLine(row)) }
            case .block(let b):
                lines += blockLines(b)
            case .drawer(let d):
                lines.append(d.beginRaw ?? ":\(d.name):")
                lines += d.lines
                lines.append(d.endRaw ?? ":END:")
            case .list(let l):
                for item in l.items { lines += listItemLines(item) }
            }
        }
        return lines
    }

    static func tableRowLine(_ row: OrgTableRow) -> String {
        if let raw = row.raw { return raw }
        if row.isSeparator { return "|-" }
        return "| " + row.cells.joined(separator: " | ") + " |"
    }

    static func blockLines(_ b: OrgBlock) -> [String] {
        var lines: [String] = []
        if let begin = b.beginRaw { lines.append(begin) }
        else {
            let params = b.parameters.isEmpty ? "" : " " + b.parameters
            lines.append("#+BEGIN_\(b.type)\(params)")
        }
        lines += b.lines
        lines.append(b.endRaw ?? "#+END_\(b.type)")
        return lines
    }

    static func listItemLines(_ item: OrgListItem) -> [String] {
        var lines: [String] = [item.raw ?? regenerateListItem(item)]
        lines += item.trailing
        for child in item.children { lines += listItemLines(child) }
        return lines
    }

    static func regenerateListItem(_ item: OrgListItem) -> String {
        var s = item.indent + item.bullet + " "
        if let cb = item.checkbox { s += cb.rawValue + " " }
        s += item.text
        return s
    }
}
