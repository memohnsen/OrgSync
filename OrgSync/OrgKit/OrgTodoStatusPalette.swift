//
//  OrgTodoStatusPalette.swift
//  OrgSync
//
//  Stable colors for built-in and user-defined org TODO keywords.
//

import Foundation

/// Color values are kept as hex strings here so OrgKit remains independent of
/// SwiftUI. Views convert them to their platform color representation.
public enum OrgTodoStatusPalette {
    /// The four statuses included in every new OrgSync configuration.
    public static let builtInHex: [String: String] = [
        "TODO": "F59E0B",
        "PROGRESS": "3B82F6",
        "WAITING": "8B5CF6",
        "DONE": "22C55E",
    ]

    /// Ten additional colors, assigned in configured keyword order to custom
    /// statuses. Assignment wraps after ten statuses while remaining stable.
    public static let customHex = [
        "E5484D", "F76B15", "D99000", "9E9D00", "46A758",
        "00A2C7", "0091FF", "6E56CF", "AB4ABA", "E54666",
    ]

    public static func hex(for keyword: String, configuration: OrgTodoConfig) -> String {
        let normalized = keyword.uppercased()
        if let color = builtInHex[normalized] { return color }

        let customKeywords = configuration.allKeywords.map { $0.uppercased() }
            .filter { builtInHex[$0] == nil }
        if let index = customKeywords.firstIndex(of: normalized) {
            return customHex[index % customHex.count]
        }

        // A document may be updating while its configuration changes. Keep an
        // unconfigured keyword visually stable instead of falling back to a
        // misleading built-in status color.
        let index = normalized.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) % customHex.count
        }
        return customHex[index]
    }
}
