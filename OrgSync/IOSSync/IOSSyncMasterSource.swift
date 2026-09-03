//
//  IOSSyncMasterSource.swift
//  OrgSync
//
//  Which side is authoritative when Calendar or Reminders sync runs. Each
//  integration stores its own preference; defaults preserve today's behavior.
//

import Foundation

enum IOSSyncMasterSource: String, CaseIterable, Identifiable {
    case iosApps
    case orgFiles

    var id: String { rawValue }

    var calendarPickerLabel: String {
        switch self {
        case .iosApps: String(localized: "iOS Calendar")
        case .orgFiles: String(localized: "calendar.org")
        }
    }

    var remindersPickerLabel: String {
        switch self {
        case .iosApps: String(localized: "iOS Reminders")
        case .orgFiles: String(localized: "Org files")
        }
    }
}
