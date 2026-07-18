//
//  OrgTodoConfig.swift
//  OrgSync
//
//  TODO keyword configuration. Defaults to `TODO`/`DONE` and can be extended
//  by `#+TODO:` / `#+SEQ_TODO:` / `#+TYP_TODO:` in-buffer lines, where a `|`
//  separates not-done states from done states (if absent, the last keyword is
//  the done state). Exposes which keywords are "done".
//

import Foundation

/// A single TODO sequence, e.g. `TODO NEXT | DONE CANCELLED`.
public struct OrgTodoSequence: Sendable, Hashable {
    public var notDone: [String]
    public var done: [String]

    public init(notDone: [String], done: [String]) {
        self.notDone = notDone
        self.done = done
    }

    public var all: [String] { notDone + done }
}

public struct OrgTodoConfig: Sendable, Hashable {
    public var sequences: [OrgTodoSequence]

    public init(sequences: [OrgTodoSequence]) {
        self.sequences = sequences
    }

    /// The built-in workflow: to do, in progress, waiting, and complete.
    public static let `default` = OrgTodoConfig(
        sequences: [OrgTodoSequence(notDone: ["TODO", "PROGRESS", "WAITING"], done: ["DONE"])]
    )

    /// The editable setting representation of the built-in workflow.
    public static let defaultPreference = "TODO PROGRESS WAITING | DONE"

    public var allKeywords: [String] { sequences.flatMap(\.all) }
    public var doneKeywords: Set<String> { Set(sequences.flatMap(\.done)) }
    public var notDoneKeywords: Set<String> { Set(sequences.flatMap(\.notDone)) }

    public func isDone(_ keyword: String) -> Bool { doneKeywords.contains(keyword) }
    public func isKeyword(_ word: String) -> Bool { allKeywords.contains(word) }

    /// The sequence that contains `keyword`, if any.
    public func sequence(for keyword: String) -> OrgTodoSequence? {
        sequences.first { $0.all.contains(keyword) }
    }

    /// Parse the value of a `#+TODO:`-style line into a sequence.
    /// Strips fast-access hints like `(t)` / `(c@/!)`.
    public static func parseSequence(_ value: String) -> OrgTodoSequence {
        var notDone: [String] = []
        var done: [String] = []
        var sawSeparator = false
        for raw in value.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let tok = String(raw)
            if tok == "|" { sawSeparator = true; continue }
            let keyword = stripFastAccess(tok)
            guard !keyword.isEmpty else { continue }
            if sawSeparator { done.append(keyword) } else { notDone.append(keyword) }
        }
        // With no explicit separator, the last keyword is the done state.
        if !sawSeparator, let last = notDone.popLast() {
            done.append(last)
        }
        return OrgTodoSequence(notDone: notDone, done: done)
    }

    private static func stripFastAccess(_ token: String) -> String {
        if let paren = token.firstIndex(of: "(") {
            return String(token[token.startIndex..<paren])
        }
        return token
    }

    /// Keys that introduce a TODO sequence.
    public static let keywordNames: Set<String> = ["TODO", "SEQ_TODO", "TYP_TODO"]

    /// Build a config from in-buffer keyword lines. Falls back to the default
    /// when no TODO keyword lines are present.
    public static func from(keywords: [(key: String, value: String)]) -> OrgTodoConfig {
        let seqs = keywords
            .filter { keywordNames.contains($0.key.uppercased()) }
            .map { parseSequence($0.value) }
        return seqs.isEmpty ? .default : OrgTodoConfig(sequences: seqs)
    }
}
