//
//  OrgSyncIntentPackage.swift
//  OrgSync
//

import AppIntents
import OrgSyncIntents

/// Makes the shared pull intent discoverable from the main app target.
struct OrgSyncAppIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [OrgSyncIntentsPackage.self]
    }
}
