// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PocketLedger",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PocketLedger", targets: ["PocketLedger"])
    ],
    targets: [
        .executableTarget(
            name: "PocketLedger",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "PocketLedgerTests",
            dependencies: ["PocketLedger"],
            path: "Tests"
        )
    ]
)
