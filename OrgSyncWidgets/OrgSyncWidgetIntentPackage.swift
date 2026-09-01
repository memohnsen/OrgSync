//
//  OrgSyncWidgetIntentPackage.swift
//  OrgSyncWidgets
//

import AppIntents
import OrgSyncIntents

/// Makes the shared pull intent discoverable from the WidgetKit target.
struct OrgSyncWidgetIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [OrgSyncIntentsPackage.self]
    }
}
