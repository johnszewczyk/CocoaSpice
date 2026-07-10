// swift-tools-version: 6.3

import Foundation
import PackageDescription

let rootPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path
let libVGMBuildDirectory = "\(rootPath)/.build/libvgm"
let libVGMVendorDirectory = "\(rootPath)/vendor/libvgm"
let libMGBABuildDirectory = "\(rootPath)/.build/mgba"
let libMGBAVendorDirectory = "\(rootPath)/vendor/mgba"

let package = Package(
    name: "CocoaSpice",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "CocoaSpice", targets: ["CocoaSpice"])
    ],
    targets: [
        .target(
            name: "CGME",
            path: "Sources/CGME",
            publicHeadersPath: ".",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"]),
                .linkedLibrary("gme")
            ]
        ),
        .target(
            name: "CLibVGM",
            path: "Sources/CLibVGM",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-I\(libVGMVendorDirectory)"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(libVGMBuildDirectory)/bin",
                    "-lvgm-player",
                    "-lvgm-emu",
                    "-lvgm-utils"
                ]),
                .linkedLibrary("iconv"),
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "CHighlyComplete",
            path: "Sources/CHighlyComplete",
            publicHeadersPath: "include",
            cSettings: [
                .define("M_CORE_GBA"),
                .define("ENABLE_VFS"),
                .define("ENABLE_DIRECTORIES"),
                .unsafeFlags([
                    "-I\(libMGBAVendorDirectory)/include",
                    "-I\(libMGBABuildDirectory)/include",
                    "-I\(libMGBAVendorDirectory)/src"
                ])
            ],
            cxxSettings: [
                .define("M_CORE_GBA"),
                .define("ENABLE_VFS"),
                .define("ENABLE_DIRECTORIES"),
                .unsafeFlags([
                    "-I\(libMGBAVendorDirectory)/include",
                    "-I\(libMGBABuildDirectory)/include",
                    "-I\(libMGBAVendorDirectory)/src"
                ])
            ],
            linkerSettings: [
                .unsafeFlags(["-L\(libMGBABuildDirectory)"]),
                .unsafeFlags(["-lmgba"]),
                .linkedLibrary("z")
            ]
        ),
        .executableTarget(
            name: "CocoaSpice",
            dependencies: ["CGME", "CLibVGM", "CHighlyComplete"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("SwiftUI"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CocoaSpiceTests",
            dependencies: ["CocoaSpice"]
        )
    ],
    swiftLanguageModes: [.v6]
)
