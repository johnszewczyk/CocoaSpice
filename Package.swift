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
        .package(path: "../FrontendCore"),
        .package(path: "../VGMBoy")
    ],
    targets: [
        .executableTarget(
            name: "CocoaSpice",
            dependencies: [
                .product(name: "CatalogReader", package: "CatalogReader"),
                .product(name: "CatalogPlaylistCore", package: "CatalogReader"),
                .product(name: "FrontendCommandCore", package: "CatalogReader"),
                .product(name: "CatalogBrowserCore", package: "CatalogReader"),
                .product(name: "CatalogSessionCore", package: "CatalogReader"),
                .product(name: "LocalFileBrowserCore", package: "FrontendCore"),
                .product(name: "FavoriteTrackCore", package: "FrontendCore"),
                .product(name: "PlaylistIdentityCore", package: "FrontendCore"),
                .product(name: "FavoriteStoreCore", package: "FrontendCore"),
                .product(name: "FrontendPreferencesCore", package: "FrontendCore"),
                .product(name: "PlaybackRequestCore", package: "FrontendCore"),
                .product(name: "PlaybackQueueCore", package: "FrontendCore"),
                .product(name: "PlaybackTransportCore", package: "FrontendCore"),
                .product(name: "ArchiveCacheCore", package: "FrontendCore"),
                .product(name: "ArchiveMaterializationCore", package: "FrontendCore"),
                .product(name: "VGMBoyKit", package: "VGMBoy"),
                .product(name: "VGMBoyEndpointCore", package: "VGMBoy")
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
