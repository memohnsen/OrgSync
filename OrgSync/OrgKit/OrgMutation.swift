//
//  OrgMutation.swift
//  OrgSync
//
//  In-place mutation helpers on the model: cycling/toggling TODO state
//  (writing/removing a CLOSED inactive timestamp, honoring repeaters by
//  advancing SCHEDULED/DEADLINE instead of completing), cycling checkbox state
//  with statistics-cookie updates, setting priority, adding/removing tags, and
//  setting SCHEDULED/DEADLINE dates. Each mutation clears the affected `raw`
//  capture so the serializer regenerates canonical text.
//

import Foundation

// MARK: - Statistics cookies

enum OrgStatistics {
    /// Replace a `[n/m]` or `[p%]` cookie in `text` with updated counts,
    /// preserving whichever style is present. No-op when no cookie exists.
    static func replaceCookie(in text: String, done: Int, total: Int) -> String {
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "[", let close = findCookie(chars, i) {
                let inner = String(chars[(i + 1)..<close])
                let replacement: String?
                if inner.hasSuffix("%") {
                    let pct = total == 0 ? 0 : Int((Double(done) / Double(total) * 100).rounded())
                    replacement = "\(pct)%"
                } else if inner.contains("/") {
                    replacement = "\(done)/\(total)"
                } else {
                    replacement = nil
                }
                if let r = replacement {
                    let prefix = String(chars[0..<i])
                    let suffix = String(chars[(close + 1)...])
                    return prefix + "[" + r + "]" + suffix
                }
            }
            i += 1
        }
        return text
    }

    /// If a cookie starts at `open`, return the index of its closing `]`.
    private static func findCookie(_ chars: [Character], _ open: Int) -> Int? {
        var j = open + 1
        var sawSlash = false
        var sawPercent = false
        var sawDigit = false
        while j < chars.count, chars[j] != "]" {
            let c = chars[j]
            if c.isNumber { sawDigit = true }
            else if c == "/" { sawSlash = true }
            else if c == "%" { sawPercent = true }
            else { return nil }
            j += 1
        }
        guard j < chars.count else { return nil }
        // Valid forms: [n/m] or [p%] (a lone [/] or [%] is also allowed).
        if sawSlash || (sawPercent && (sawDigit || true)) { return j }
        return nil
    }
}

// MARK: - TODO transitions

extension OrgHeadline {
    private var hasRepeater: Bool {
        planning.scheduled?.repeater != nil || planning.deadline?.repeater != nil
    }

    /// Advance any repeating SCHEDULED/DEADLINE timestamps to their next occurrence.
    public mutating func advanceRepeaters(now: Date = Date()) {
        if let s = planning.scheduled, s.repeater != nil {
            planning.scheduled = s.advancedByRepeater(reference: now)
        }
        if let d = planning.deadline, d.repeater != nil {
            planning.deadline = d.advancedByRepeater(reference: now)
        }
        planning.raw = nil
    }

    /// Apply a transition to `newKeyword`, handling CLOSED and repeaters.
    public mutating func setTodoKeyword(_ newKeyword: String?, config: OrgTodoConfig,
                                        now: Date = Date()) {
        let wasDone = todoKeyword.map(config.isDone) ?? false
        let willBeDone = newKeyword.map(config.isDone) ?? false

        if willBeDone, hasRepeater {
            // Repeating task: advance the schedule instead of completing.
            advanceRepeaters(now: now)
            let seq = todoKeyword.flatMap(config.sequence(for:)) ?? config.sequences.first
            todoKeyword = seq?.notDone.first ?? todoKeyword
            planning.closed = nil
            raw = nil
            return
        }

        todoKeyword = newKeyword
        if willBeDone, !wasDone {
            planning.closed = OrgTimestamp(date: now, isActive: false, includeTime: true)
        } else if !willBeDone, wasDone {
            planning.closed = nil
        }
        raw = nil
        planning.raw = nil
    }

    /// Cycle to the next state in the keyword's sequence
    /// (…none → first → … → last → none…).
    public mutating func cycleTodo(config: OrgTodoConfig, now: Date = Date()) {
        let seq = todoKeyword.flatMap(config.sequence(for:)) ?? config.sequences.first
        guard let sequence = seq else { return }
        let order: [String?] = sequence.all.map { Optional($0) } + [nil]
        let currentIndex = order.firstIndex(where: { $0 == todoKeyword }) ?? (order.count - 1)
        let next = order[(currentIndex + 1) % order.count]
        setTodoKeyword(next, config: config, now: now)
    }

    /// Toggle between the first not-done keyword and the first done keyword.
    public mutating func toggleTodo(config: OrgTodoConfig, now: Date = Date()) {
        let seq = todoKeyword.flatMap(config.sequence(for:)) ?? config.sequences.first
        guard let sequence = seq else { return }
        let currentlyDone = todoKeyword.map(config.isDone) ?? false
        let target = currentlyDone ? sequence.notDone.first : sequence.done.first
        setTodoKeyword(target, config: config, now: now)
    }

    // MARK: - Priority / tags

    public mutating func setPriority(_ priority: Character?) {
        self.priority = priority
        raw = nil
    }

    public mutating func addTag(_ tag: String) {
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        raw = nil
    }

    public mutating func removeTag(_ tag: String) {
        guard let idx = tags.firstIndex(of: tag) else { return }
        tags.remove(at: idx)
        raw = nil
    }

    // MARK: - Scheduling

    public mutating func setScheduled(_ timestamp: OrgTimestamp?) {
        planning.scheduled = timestamp
        planning.raw = nil
    }

    public mutating func setDeadline(_ timestamp: OrgTimestamp?) {
        planning.deadline = timestamp
        planning.raw = nil
    }

    public mutating func setScheduled(date: Date, includeTime: Bool = false) {
        setScheduled(OrgTimestamp(date: date, isActive: true, includeTime: includeTime))
    }

    public mutating func setDeadline(date: Date, includeTime: Bool = false) {
        setDeadline(OrgTimestamp(date: date, isActive: true, includeTime: includeTime))
    }

    // MARK: - Statistics cookies

    /// Recompute checkbox statistics: partial/checked states of parent list
    /// items and any `[n/m]` / `[p%]` cookies in list items and the headline title.
    public mutating func updateStatisticsCookies() {
        var done = 0, total = 0
        for i in body.indices {
            if case .list(var list) = body[i] {
                for j in list.items.indices { list.items[j].recompute() }
                for item in list.items where item.checkbox != nil {
                    total += 1
                    if item.checkbox == .checked { done += 1 }
                }
                body[i] = .list(list)
            }
        }
        if total > 0 {
            let newTitle = OrgStatistics.replaceCookie(in: title, done: done, total: total)
            if newTitle != title { title = newTitle; raw = nil }
        }
    }
}

// MARK: - Checkbox cycling

extension OrgListItem {
    /// Toggle this leaf item's checkbox (unchecked ↔ checked).
    public mutating func toggleCheckbox() {
        switch checkbox {
        case .checked: checkbox = .unchecked
        case .unchecked, .partial: checkbox = .checked
        case nil: return
        }
        raw = nil
    }

    /// Recompute this item's checkbox and cookie from its direct children.
    public mutating func recompute() {
        for i in children.indices { children[i].recompute() }
        let boxed = children.filter { $0.checkbox != nil }
        guard !boxed.isEmpty else { return }
        let done = boxed.filter { $0.checkbox == .checked }.count
        let total = boxed.count
        if checkbox != nil {
            let newState: OrgCheckbox = done == 0 ? .unchecked : (done == total ? .checked : .partial)
            if newState != checkbox { checkbox = newState; raw = nil }
        }
        let newText = OrgStatistics.replaceCookie(in: text, done: done, total: total)
        if newText != text { text = newText; raw = nil }
    }
}

extension OrgList {
    /// Cycle the checkbox of the item addressed by `path` (indices into
    /// `items` then nested `children`), then recompute parent statistics.
    public mutating func cycleCheckbox(at path: [Int]) {
        guard !path.isEmpty else { return }
        OrgList.toggle(&items, path: path)
        for i in items.indices { items[i].recompute() }
    }

    private static func toggle(_ items: inout [OrgListItem], path: [Int]) {
        guard let first = path.first, items.indices.contains(first) else { return }
        if path.count == 1 {
            items[first].toggleCheckbox()
        } else {
            toggle(&items[first].children, path: Array(path.dropFirst()))
        }
    }
}
