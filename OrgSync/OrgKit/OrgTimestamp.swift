//
//  OrgTimestamp.swift
//  OrgSync
//
//  Value model + parser/formatter for org-mode timestamps.
//  Handles active `<...>` and inactive `[...]` timestamps, an optional time
//  (and time range `10:00-11:00`), an optional repeater (`+1w`, `++1m`, `.+1d`),
//  an optional warning delay (`-2d`), the abbreviated day-of-week name, and
//  timestamp ranges (`<...>--<...>`). Formatting matches how Emacs org prints
//  timestamps, e.g. `<2026-07-18 Sat 10:00 +1w>`.
//

import Foundation

/// The unit of a repeater or warning-delay interval.
public enum OrgInterval: Character, Sendable, Hashable {
    case hour = "h"
    case day = "d"
    case week = "w"
    case month = "m"
    case year = "y"
}

/// A repeater such as `+1w`, `++1m`, or `.+1d`.
public struct OrgRepeater: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        /// `+` — shift by the interval once.
        case cumulate = "+"
        /// `++` — shift by the interval until strictly in the future.
        case catchUp = "++"
        /// `.+` — reset to today plus the interval.
        case restart = ".+"
    }

    public var kind: Kind
    public var value: Int
    public var unit: OrgInterval

    public init(kind: Kind, value: Int, unit: OrgInterval) {
        self.kind = kind
        self.value = value
        self.unit = unit
    }

    public var text: String { "\(kind.rawValue)\(value)\(unit.rawValue)" }
}

/// A warning delay such as `-2d` or `--1d`.
public struct OrgWarning: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case all = "-"
        case first = "--"
    }

    public var kind: Kind
    public var value: Int
    public var unit: OrgInterval

    public init(kind: Kind, value: Int, unit: OrgInterval) {
        self.kind = kind
        self.value = value
        self.unit = unit
    }

    public var text: String { "\(kind.rawValue)\(value)\(unit.rawValue)" }
}

public struct OrgTimestamp: Sendable, Hashable {
    public var isActive: Bool
    public var year: Int
    public var month: Int
    public var day: Int
    /// Abbreviated day name as written (`Sat`). Reproduced verbatim on format;
    /// recomputed when constructing a fresh timestamp.
    public var dayName: String?
    public var startHour: Int?
    public var startMinute: Int?
    /// End time for an in-timestamp time range (`10:00-11:00`).
    public var endHour: Int?
    public var endMinute: Int?
    public var repeater: OrgRepeater?
    public var warning: OrgWarning?
    /// End timestamp for a range (`<...>--<...>`).
    public indirect enum Box: Sendable, Hashable { case some(OrgTimestamp) }
    public var rangeEnd: Box?

    public init(isActive: Bool, year: Int, month: Int, day: Int,
                dayName: String? = nil,
                startHour: Int? = nil, startMinute: Int? = nil,
                endHour: Int? = nil, endMinute: Int? = nil,
                repeater: OrgRepeater? = nil, warning: OrgWarning? = nil,
                rangeEnd: OrgTimestamp? = nil) {
        self.isActive = isActive
        self.year = year
        self.month = month
        self.day = day
        self.dayName = dayName
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.repeater = repeater
        self.warning = warning
        self.rangeEnd = rangeEnd.map(Box.some)
    }

    public var end: OrgTimestamp? {
        get { if case .some(let t)? = rangeEnd { return t } else { return nil } }
        set { rangeEnd = newValue.map(Box.some) }
    }

    public var hasTime: Bool { startHour != nil }
}

// MARK: - Calendar helpers

extension OrgTimestamp {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    static let dayNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()

    /// A `Date` at midnight (or the start time) for this timestamp's date.
    public func date() -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = startHour ?? 0
        comps.minute = startMinute ?? 0
        return OrgTimestamp.calendar.date(from: comps)
    }

    /// The abbreviated day name computed from the date (e.g. `Sat`).
    public func computedDayName() -> String {
        guard let d = date() else { return "" }
        return OrgTimestamp.dayNameFormatter.string(from: d)
    }

    /// Create a timestamp from a `Date`, capturing time only when requested.
    public init(date: Date, isActive: Bool = true, includeTime: Bool = false) {
        let cal = OrgTimestamp.calendar
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        self.init(isActive: isActive,
                  year: comps.year ?? 2000,
                  month: comps.month ?? 1,
                  day: comps.day ?? 1,
                  dayName: OrgTimestamp.dayNameFormatter.string(from: date),
                  startHour: includeTime ? comps.hour : nil,
                  startMinute: includeTime ? comps.minute : nil)
    }
}

// MARK: - Formatting

extension OrgTimestamp {
    public func serialize() -> String {
        var s = single()
        if let e = end {
            s += "--" + e.single()
        }
        return s
    }

    private func single() -> String {
        let open = isActive ? "<" : "["
        let close = isActive ? ">" : "]"
        var parts: [String] = [String(format: "%04d-%02d-%02d", year, month, day)]
        let name = dayName ?? computedDayName()
        if !name.isEmpty { parts.append(name) }
        if let h = startHour {
            var t = String(format: "%02d:%02d", h, startMinute ?? 0)
            if let eh = endHour {
                t += String(format: "-%02d:%02d", eh, endMinute ?? 0)
            }
            parts.append(t)
        }
        if let r = repeater { parts.append(r.text) }
        if let w = warning { parts.append(w.text) }
        return open + parts.joined(separator: " ") + close
    }
}

// MARK: - Parsing

extension OrgTimestamp {
    /// Matches a full timestamp (optionally a range) anchored at the start of `text`.
    /// Returns the parsed value and the number of characters consumed.
    static func parsePrefix(_ text: Substring) -> (OrgTimestamp, Int)? {
        guard let (first, len1) = parseSingle(text) else { return nil }
        let afterFirst = text.index(text.startIndex, offsetBy: len1)
        let rest = text[afterFirst...]
        if rest.hasPrefix("--") {
            let afterDashes = rest.index(rest.startIndex, offsetBy: 2)
            if let (second, len2) = parseSingle(rest[afterDashes...]) {
                var combined = first
                combined.end = second
                return (combined, len1 + 2 + len2)
            }
        }
        return (first, len1)
    }

    /// Parse a whole string as a single timestamp or range.
    public static func parse(_ text: String) -> OrgTimestamp? {
        let trimmed = Substring(text)
        guard let (ts, len) = parsePrefix(trimmed), len == trimmed.count else { return nil }
        return ts
    }

    private static func parseSingle(_ text: Substring) -> (OrgTimestamp, Int)? {
        guard let openChar = text.first else { return nil }
        let isActive: Bool
        let closeChar: Character
        switch openChar {
        case "<": isActive = true; closeChar = ">"
        case "[": isActive = false; closeChar = "]"
        default: return nil
        }
        guard let closeIdx = text.firstIndex(of: closeChar) else { return nil }
        let bodyStart = text.index(after: text.startIndex)
        let body = text[bodyStart..<closeIdx]
        guard let ts = parseBody(body, isActive: isActive) else { return nil }
        let consumed = text.distance(from: text.startIndex, to: closeIdx) + 1
        return (ts, consumed)
    }

    private static func parseBody(_ body: Substring, isActive: Bool) -> OrgTimestamp? {
        var tokens = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return nil }

        // Date
        let dateTok = tokens.removeFirst()
        let dateParts = dateTok.split(separator: "-")
        guard dateParts.count == 3,
              let y = Int(dateParts[0]), let mo = Int(dateParts[1]), let d = Int(dateParts[2])
        else { return nil }

        var ts = OrgTimestamp(isActive: isActive, year: y, month: mo, day: d)
        ts.dayName = nil

        for tok in tokens {
            if let (r, kind) = parseRepeater(tok) {
                ts.repeater = r
                _ = kind
            } else if let w = parseWarning(tok) {
                ts.warning = w
            } else if let (sh, sm, eh, em) = parseTime(tok) {
                ts.startHour = sh; ts.startMinute = sm
                ts.endHour = eh; ts.endMinute = em
            } else if isDayName(tok) {
                ts.dayName = tok
            } else {
                // Unknown token — reject so odd text is preserved verbatim upstream.
                return nil
            }
        }
        return ts
    }

    private static func isDayName(_ s: String) -> Bool {
        // Day names contain no digits and no interval markers.
        return !s.isEmpty && s.allSatisfy { $0.isLetter }
    }

    private static func parseTime(_ s: String) -> (Int, Int?, Int?, Int?)? {
        // HH:MM or HH:MM-HH:MM
        func hm(_ p: Substring) -> (Int, Int)? {
            let c = p.split(separator: ":")
            guard c.count == 2, let h = Int(c[0]), let m = Int(c[1]) else { return nil }
            return (h, m)
        }
        if let dash = s.firstIndex(of: "-"), s.first != "-" {
            let left = s[s.startIndex..<dash]
            let right = s[s.index(after: dash)...]
            guard let (sh, sm) = hm(left), let (eh, em) = hm(right) else { return nil }
            return (sh, sm, eh, em)
        } else {
            guard s.contains(":"), let (h, m) = hm(Substring(s)) else { return nil }
            return (h, m, nil, nil)
        }
    }

    private static func parseRepeater(_ s: String) -> (OrgRepeater, OrgRepeater.Kind)? {
        let kinds: [(String, OrgRepeater.Kind)] = [("++", .catchUp), (".+", .restart), ("+", .cumulate)]
        for (prefix, kind) in kinds where s.hasPrefix(prefix) {
            let rest = s.dropFirst(prefix.count)
            guard let (val, unit) = splitValueUnit(rest) else { return nil }
            return (OrgRepeater(kind: kind, value: val, unit: unit), kind)
        }
        return nil
    }

    private static func parseWarning(_ s: String) -> OrgWarning? {
        let kinds: [(String, OrgWarning.Kind)] = [("--", .first), ("-", .all)]
        for (prefix, kind) in kinds where s.hasPrefix(prefix) {
            let rest = s.dropFirst(prefix.count)
            guard let (val, unit) = splitValueUnit(rest) else { return nil }
            return OrgWarning(kind: kind, value: val, unit: unit)
        }
        return nil
    }

    private static func splitValueUnit(_ s: Substring) -> (Int, OrgInterval)? {
        guard let unitChar = s.last, let unit = OrgInterval(rawValue: unitChar) else { return nil }
        let digits = s.dropLast()
        guard !digits.isEmpty, let val = Int(digits) else { return nil }
        return (val, unit)
    }
}

// MARK: - Repeater advance

extension OrgTimestamp {
    /// Advance this timestamp's date by its repeater, returning a new timestamp.
    /// Honors `+` (once), `++` (until after `reference`), and `.+` (reference + interval).
    public func advancedByRepeater(reference: Date = Date()) -> OrgTimestamp {
        guard let rep = repeater else { return self }
        let cal = OrgTimestamp.calendar
        guard var current = date() else { return self }

        func add(_ base: Date, _ n: Int) -> Date {
            var comp = DateComponents()
            switch rep.unit {
            case .hour: comp.hour = n * rep.value
            case .day: comp.day = n * rep.value
            case .week: comp.day = n * rep.value * 7
            case .month: comp.month = n * rep.value
            case .year: comp.year = n * rep.value
            }
            return cal.date(byAdding: comp, to: base) ?? base
        }

        switch rep.kind {
        case .cumulate:
            current = add(current, 1)
        case .catchUp:
            current = add(current, 1)
            var guardCount = 0
            while current <= reference && guardCount < 10_000 {
                current = add(current, 1)
                guardCount += 1
            }
        case .restart:
            current = add(reference, 1)
        }

        var result = self
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: current)
        result.year = comps.year ?? year
        result.month = comps.month ?? month
        result.day = comps.day ?? day
        if hasTime {
            result.startHour = comps.hour
            result.startMinute = comps.minute
            // Shift an in-timestamp time range by the same delta in minutes-of-day.
            if let eh = endHour, let sh = startHour {
                let deltaH = (comps.hour ?? sh) - sh
                result.endHour = eh + deltaH
            }
        }
        result.dayName = result.computedDayName()
        return result
    }
}
