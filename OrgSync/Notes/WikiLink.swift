//
//  WikiLink.swift
//  OrgSync
//
//  Extracts org `[[target]]` / `[[target][description]]` wiki-link targets from
//  note text and resolves whether one points at a given note. Used to build the
//  backlinks ("Linked References") shown on a note.
//

import Foundation

enum WikiLink {
    /// Targets referenced by `[[target]]` / `[[target][desc]]` in raw org text.
    static func targets(in text: String) -> [String] {
        let pattern = #"\[\[([^\]\[]+?)\](?:\[[^\]\[]*\])?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Whether a link target refers to the note with this name / relative path.
    /// Headings (`*…`), ids (`id:…`), and URLs are not note links.
    static func resolves(_ target: String, toNoteNamed displayName: String, relativePath: String) -> Bool {
        let normalized = normalize(target)
        guard !normalized.isEmpty,
              !target.trimmingCharacters(in: .whitespaces).hasPrefix("*"),
              !target.contains("://"),
              !normalized.hasPrefix("id:") else { return false }
        return normalized == normalize(displayName) || normalized == normalize(relativePath)
    }

    private static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("file:") { value = String(value.dropFirst("file:".count)) }
        if value.lowercased().hasSuffix(".org") { value = String(value.dropLast(".org".count)) }
        return value.lowercased()
    }
}
