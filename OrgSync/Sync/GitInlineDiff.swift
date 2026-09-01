//
//  GitInlineDiff.swift
//  OrgSync
//
//  A small, deterministic line-based unified-diff builder for note changes.
//

import Foundation

enum GitInlineDiff {
    struct Line: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case unchanged, removed, added, collapsed }
        var kind: Kind
        var text: String
    }

    static func lines(original: String?, current: String?) -> [Line] {
        let before = split(original)
        let after = split(current)
        // Avoid disproportionate memory use for unusually large text files.
        let rows = before.count + 1
        let columns = after.count + 1
        guard rows <= 1_000_000 / columns else {
            return before.map { Line(kind: .removed, text: $0) }
                + after.map { Line(kind: .added, text: $0) }
        }

        var lcs = Array(repeating: 0, count: (before.count + 1) * columns)
        for i in stride(from: before.count - 1, through: 0, by: -1) where !before.isEmpty {
            for j in stride(from: after.count - 1, through: 0, by: -1) where !after.isEmpty {
                let index = i * columns + j
                if before[i] == after[j] {
                    lcs[index] = lcs[(i + 1) * columns + j + 1] + 1
                } else {
                    lcs[index] = max(lcs[(i + 1) * columns + j], lcs[i * columns + j + 1])
                }
            }
        }

        var result: [Line] = []
        var i = 0
        var j = 0
        while i < before.count || j < after.count {
            if i < before.count, j < after.count, before[i] == after[j] {
                result.append(Line(kind: .unchanged, text: before[i]))
                i += 1; j += 1
            } else if j == after.count || (i < before.count && lcs[(i + 1) * columns + j] >= lcs[i * columns + j + 1]) {
                result.append(Line(kind: .removed, text: before[i]))
                i += 1
            } else {
                result.append(Line(kind: .added, text: after[j]))
                j += 1
            }
        }
        return result
    }

    /// Limits unchanged context around each changed hunk to keep long notes readable.
    /// Changed lines are never omitted.
    static func displayLines(original: String?, current: String?, context: Int = 2) -> [Line] {
        let source = lines(original: original, current: current)
        let changedOffsets = source.indices.filter { source[$0].kind != .unchanged }
        guard !changedOffsets.isEmpty else { return source }

        var keep = Array(repeating: false, count: source.count)
        for changed in changedOffsets {
            let radius = max(0, context)
            let lower = max(source.startIndex, changed - radius)
            let upper = min(source.endIndex, changed + radius + 1)
            for index in lower..<upper { keep[index] = true }
        }

        var result: [Line] = []
        var hiddenCount = 0
        for index in source.indices {
            let line = source[index]
            let keepsContext = keep[index]
            if keepsContext {
                if hiddenCount > 0 {
                    let noun = hiddenCount == 1 ? "line" : "lines"
                    result.append(Line(kind: .collapsed, text: "⋯ \(hiddenCount) unchanged \(noun) folded"))
                    hiddenCount = 0
                }
                result.append(line)
            } else {
                hiddenCount += 1
            }
        }
        if hiddenCount > 0 {
            let noun = hiddenCount == 1 ? "line" : "lines"
            result.append(Line(kind: .collapsed, text: "⋯ \(hiddenCount) unchanged \(noun) folded"))
        }
        return result
    }

    private static func split(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
