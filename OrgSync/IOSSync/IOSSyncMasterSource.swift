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

    var isIOSAppsMaster: Bool {
        get { self == .iosApps }
        set { self = newValue ? .iosApps : .orgFiles }
    }
}
