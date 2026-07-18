//
//  ThreeWayMerge.swift
//  OrgSync
//
//  A line-level three-way merge (base / local / remote), used by the sync
//  engine's pull step when a file changed on both sides. It computes each
//  side's changes relative to the common ancestor (`base`) and combines them:
//  disjoint edits merge cleanly, identical edits collapse to one, and edits
//  that touch overlapping regions are reported as a conflict.
//
//  The engine uses the *clean* merged result when there is no conflict; on
//  conflict it leaves the local file untouched and writes the remote version
//  alongside it, so no merge markers are ever written into a note.
//

import Foundation

enum ThreeWayMerge {
    struct Result {
        var lines: [String]
        var hasConflict: Bool
    }

    /// Merge three versions of a file split into lines.
    static func merge(base: [String], local: [String], remote: [String]) -> Result {
        let aHunks = hunks(base: base, other: local)
        let bHunks = hunks(base: base, other: remote)

        var output: [String] = []
        var conflict = false

        var pos = 0            // current index into `base`
        var ai = 0             // next unconsumed local hunk
        var bi = 0             // next unconsumed remote hunk

        while pos < base.count || ai < aHunks.count || bi < bHunks.count {
            let nextA = ai < aHunks.count ? aHunks[ai].baseStart : Int.max
            let nextB = bi < bHunks.count ? bHunks[bi].baseStart : Int.max
            let nextChange = min(nextA, nextB)

            // Emit unchanged base lines up to the next change.
            if nextChange > pos {
                let end = min(nextChange, base.count)
                if end > pos { output.append(contentsOf: base[pos..<end]) }
                pos = nextChange
                if pos >= base.count && ai >= aHunks.count && bi >= bHunks.count { break }
                continue
            }

            // A change region begins at `pos`. Seed it with the hunk(s) that
            // start here, then expand to swallow any later hunk from either side
            // that overlaps the region already claimed (strict overlap only, so
            // merely adjacent edits stay independent and merge cleanly).
            let regionStart = pos
            var regionEnd = pos
            var grew = true
            while grew {
                grew = false
                while ai < aHunks.count {
                    let h = aHunks[ai]
                    let overlaps = h.baseStart < regionEnd
                    let seedsEmpty = h.baseStart == regionStart && regionEnd == regionStart
                    guard overlaps || seedsEmpty else { break }
                    regionEnd = max(regionEnd, h.baseEnd)
                    ai += 1
                    grew = true
                }
                while bi < bHunks.count {
                    let h = bHunks[bi]
                    let overlaps = h.baseStart < regionEnd
                    let seedsEmpty = h.baseStart == regionStart && regionEnd == regionStart
                    guard overlaps || seedsEmpty else { break }
                    regionEnd = max(regionEnd, h.baseEnd)
                    bi += 1
                    grew = true
                }
            }
            regionEnd = min(max(regionEnd, regionStart), base.count)

            // Collect the hunks that fell inside this region.
            let aInRegion = consumed(aHunks, upTo: ai, from: regionStart)
            let bInRegion = consumed(bHunks, upTo: bi, from: regionStart)

            let aVersion = apply(aInRegion, base: base, start: regionStart, end: regionEnd)
            let bVersion = apply(bInRegion, base: base, start: regionStart, end: regionEnd)
            let aChanged = !aInRegion.isEmpty
            let bChanged = !bInRegion.isEmpty

            if aChanged && bChanged {
                if aVersion == bVersion {
                    output.append(contentsOf: aVersion)
                } else {
                    conflict = true
                    output.append(contentsOf: aVersion) // prefer local; caller side-cars remote
                }
            } else if aChanged {
                output.append(contentsOf: aVersion)
            } else if bChanged {
                output.append(contentsOf: bVersion)
            } else if regionEnd > regionStart {
                output.append(contentsOf: base[regionStart..<regionEnd])
            }

            pos = max(regionEnd, regionStart)
            if pos >= base.count && ai >= aHunks.count && bi >= bHunks.count { break }
        }

        return Result(lines: output, hasConflict: conflict)
    }

    /// Convenience over full-text strings. Splits on "\n" preserving a trailing
    /// newline distinction by tracking it separately.
    static func merge(base: String, local: String, remote: String) -> (text: String, hasConflict: Bool) {
        let result = merge(base: splitLines(base), local: splitLines(local), remote: splitLines(remote))
        return (result.lines.joined(separator: "\n"), result.hasConflict)
    }

    // MARK: - Hunks

    /// A contiguous edit: base lines `[baseStart, baseEnd)` are replaced by `lines`.
    private struct Hunk {
        var baseStart: Int
        var baseEnd: Int
        var lines: [String]
    }

    /// Difference of `base` -> `other` expressed as replacement hunks over base,
    /// derived from their longest common subsequence.
    private static func hunks(base: [String], other: [String]) -> [Hunk] {
        let pairs = lcsPairs(base, other)
        var result: [Hunk] = []
        var bPrev = 0
        var oPrev = 0
        for (bi, oi) in pairs {
            if bi > bPrev || oi > oPrev {
                result.append(Hunk(baseStart: bPrev, baseEnd: bi, lines: Array(other[oPrev..<oi])))
            }
            bPrev = bi + 1
            oPrev = oi + 1
        }
        if bPrev < base.count || oPrev < other.count {
            result.append(Hunk(baseStart: bPrev, baseEnd: base.count, lines: Array(other[oPrev..<other.count])))
        }
        return result
    }

    /// The hunks in `hunks[..<end]` whose baseStart is >= `from` (i.e. the ones
    /// just consumed for the current region).
    private static func consumed(_ hunks: [Hunk], upTo end: Int, from: Int) -> [Hunk] {
        hunks[..<end].filter { $0.baseStart >= from }
    }

    /// Reconstruct the given side's content for base span `[start, end)` by
    /// applying its hunks and copying the untouched base lines between them.
    private static func apply(_ hunks: [Hunk], base: [String], start: Int, end: Int) -> [String] {
        var lines: [String] = []
        var p = start
        for h in hunks.sorted(by: { $0.baseStart < $1.baseStart }) {
            let s = max(h.baseStart, start)
            if s > p { lines.append(contentsOf: base[p..<min(s, end)]) }
            lines.append(contentsOf: h.lines)
            p = min(max(h.baseEnd, p), end)
        }
        if p < end { lines.append(contentsOf: base[p..<end]) }
        return lines
    }

    // MARK: - LCS

    /// Matched index pairs `(i in a, j in b)` forming a longest common
    /// subsequence, in increasing order on both indices.
    private static func lcsPairs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let n = a.count
        let m = b.count
        if n == 0 || m == 0 { return [] }
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if a[i] == b[j] {
                    dp[i][j] = dp[i + 1][j + 1] + 1
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }

    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }
}
