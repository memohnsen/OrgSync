//
//  OrgTodoStatusColor.swift
//  OrgSync
//

import SwiftUI

extension Color {
    static func todoStatus(_ keyword: String, configuration: OrgTodoConfig,
                           overrides: [String: String] = [:]) -> Color {
        let hex = OrgTodoStatusPalette.hex(for: keyword, configuration: configuration, overrides: overrides)
        let value = UInt64(hex, radix: 16) ?? 0
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
