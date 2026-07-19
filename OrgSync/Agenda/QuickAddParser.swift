//
//  QuickAddParser.swift
//  OrgSync
//
//  Turns a single natural-language line ("call Sam tomorrow 3pm #work !!") into
//  the structured pieces of a TODO: a clean title, tags, a priority, and a
//  scheduled date. Pure and deterministic apart from NSDataDetector's use of the
//  current date to resolve relative phrases like "tomorrow".
//

import Foundation

struct ParsedQuickAdd: Equatable {
    var title: String
    var tags: [String]
    var priority: Character?
    var scheduledDate: Date?
    var includesTime: Bool
}

enum QuickAddParser {
    static func parse(_ raw: String) -> ParsedQuickAdd {
        var working = raw
        var scheduledDate: Date?
        var includesTime = false

        // 1. Date / time, taken from the whole line so multi-word phrases
        //    ("next friday", "tomorrow 3pm") resolve, then removed from it.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let full = NSRange(working.startIndex..., in: working)
            if let match = detector.matches(in: working, options: [], range: full).first,
               let date = match.date, let range = Range(match.range, in: working) {
                scheduledDate = date
                let matched = working[range].lowercased()
                includesTime = matched.contains(":") || matched.contains("am") || matched.contains("pm")
                    || matched.contains("noon") || matched.contains("midnight")
                working.removeSubrange(range)
            }
        }

        // 2. Tags (#tag) and priority (! = C, !! = B, !!! = A) are whole tokens.
        var titleTokens: [String] = []
        var tags: [String] = []
        var priority: Character?
        for token in working.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            if token.count > 1, token.hasPrefix("#"),
               token.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                let tag = String(token.dropFirst())
                if !tags.contains(tag) { tags.append(tag) }
            } else if (1...3).contains(token.count), token.allSatisfy({ $0 == "!" }) {
                priority = token.count >= 3 ? "A" : token.count == 2 ? "B" : "C"
            } else {
                titleTokens.append(token)
            }
        }

        return ParsedQuickAdd(
            title: titleTokens.joined(separator: " "),
            tags: tags,
            priority: priority,
            scheduledDate: scheduledDate,
            includesTime: includesTime
        )
    }
}
