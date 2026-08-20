// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "CocoaSpice",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "CocoaSpice", targets: ["CocoaSpice"])
    ],
    dependencies: [
        .package(path: "../CatalogReader"),
        .package(path: "../VGMBoy")
    ],
    targets: [
        .executableTarget(
            name: "CocoaSpice",
            dependencies: [
                .product(name: "CatalogReader", package: "CatalogReader"),
                .product(name: "VGMBoyKit", package: "VGMBoy")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("SwiftUI"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CocoaSpiceTests",
            dependencies: ["CocoaSpice"],
            resources: [
                .copy("cross-app-sidebar-search-view-v1.json"),
                .copy("cross-app-playlist-activation-v1.json")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
