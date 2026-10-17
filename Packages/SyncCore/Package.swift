// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SyncCore",
    platforms: [
        .iOS(.v26),
        // macOS is listed only so that `swift test` runs on a Mac without a simulator.
        .macOS(.v26),
    ],
    products: [
        .library(name: "SyncCore", targets: ["SyncCore"]),
        .library(name: "SyncCoreTesting", targets: ["SyncCoreTesting"]),
    ],
    targets: [
        // Domain types, the sync engine and ports. No UI, HealthKit, EventKit or CloudKit.
        .target(name: "SyncCore"),
        // In-memory fakes of every port, for tests and SwiftUI previews.
        .target(name: "SyncCoreTesting", dependencies: ["SyncCore"]),
        .testTarget(name: "SyncCoreTests", dependencies: ["SyncCore", "SyncCoreTesting"]),
    ]
)
