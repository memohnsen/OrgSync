//
//  OrgTodoStatusConfiguration.swift
//  OrgSync
//
//  Editing helpers for the single global org TODO sequence.
//

import Foundation

public struct OrgTodoStatus: Identifiable, Equatable, Hashable, Sendable {
    public var name: String
    public var isDone: Bool
    public var id: String { name }

    public init(name: String, isDone: Bool) {
        self.name = name
        self.isDone = isDone
    }
}

public enum OrgTodoStatusConfiguration {
    public static func statuses(from preference: String) -> [OrgTodoStatus] {
        let sequence = OrgTodoConfig.parseSequence(preference)
        return sequence.notDone.map { OrgTodoStatus(name: $0, isDone: false) }
            + sequence.done.map { OrgTodoStatus(name: $0, isDone: true) }
    }

    public static func preference(from statuses: [OrgTodoStatus]) -> String {
        let open = statuses.filter { !$0.isDone }.map(\.name)
        let done = statuses.filter(\.isDone).map(\.name)
        return (open + ["|"] + done).joined(separator: " ")
    }

    /// Org keywords must be a single token. Normalize casing while leaving the
    /// user in control of conventional separators such as `_` and `-`.
    public static func normalizedName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !name.isEmpty,
              !name.contains(where: { $0.isWhitespace || $0 == "|" }) else { return nil }
        return name
    }

    public static func adding(_ name: String, isDone: Bool,
                              to statuses: [OrgTodoStatus]) -> [OrgTodoStatus]? {
        guard let normalized = normalizedName(name),
              !statuses.contains(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) else {
            return nil
        }
        return statuses + [OrgTodoStatus(name: normalized, isDone: isDone)]
    }

    /// Keep at least one active and one completed state so the org sequence
    /// remains usable for cycling, Agenda, and Reminders.
    public static func removing(_ status: OrgTodoStatus,
                                from statuses: [OrgTodoStatus]) -> [OrgTodoStatus] {
        let inGroup = statuses.filter { $0.isDone == status.isDone }
        guard inGroup.count > 1 else { return statuses }
        return statuses.filter { $0.id != status.id }
    }
}
