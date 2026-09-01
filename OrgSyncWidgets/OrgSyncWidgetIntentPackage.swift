import AppIntents
import OrgSyncIntents

struct OrgSyncWidgetIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [OrgSyncIntentsPackage.self]
    }
}
