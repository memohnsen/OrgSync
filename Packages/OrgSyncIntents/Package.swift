// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OrgSyncIntents",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "OrgSyncIntents", targets: ["OrgSyncIntents"]),
    ],
    targets: [
        .target(name: "OrgSyncIntents"),
    ]
)
