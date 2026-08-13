// swift-tools-version: 6.3

import Foundation
import PackageDescription

let rootPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path
let libVGMBuildDirectory = "\(rootPath)/.build/libvgm"
let libVGMVendorDirectory = "\(rootPath)/vendor/libvgm"
let libMGBABuildDirectory = "\(rootPath)/.build/mgba"
let libMGBAVendorDirectory = "\(rootPath)/vendor/mgba"
let lazyUSFBuildDirectory = "\(rootPath)/.build/lazyusf"
let lazyUSFVendorDirectory = "\(rootPath)/vendor/lazyusf2"
let twoSFBuildDirectory = "\(rootPath)/.build/2sf"
let twoSFVendorDirectory = "\(rootPath)/vendor/2sf2wav"
let vgmstreamBuildDirectory = "\(rootPath)/.build/vgmstream"
let vgmstreamVendorDirectory = "\(rootPath)/vendor/vgmstream/src"
let playPSFBuildDirectory = "\(rootPath)/.build/play-psf"
let playPSFVendorDirectory = "\(rootPath)/vendor/play/tools/PsfPlayer/Source"
let highlyTheoreticalBuildDirectory = "\(rootPath)/.build/highly-theoretical"
let highlyTheoreticalVendorDirectory = "\(rootPath)/vendor/highly_theoretical/Core"

let package = Package(
    name: "CocoaSpice",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "CocoaSpice", targets: ["CocoaSpice"])
    ],
    dependencies: [
        .package(path: "../MediaScanner")
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
            name: "COpenMPT",
            path: "Sources/COpenMPT",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/opt/libopenmpt/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/opt/libopenmpt/lib"]),
                .linkedLibrary("openmpt")
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
        .target(
            name: "CLazyUSF",
            path: "Sources/CLazyUSF",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I\(lazyUSFVendorDirectory)", "-I\(rootPath)/vendor/psflib"])
            ],
            linkerSettings: [
                .unsafeFlags(["\(lazyUSFBuildDirectory)/liblazyusf.a", "\(lazyUSFBuildDirectory)/libpsflib.a"]),
                .linkedLibrary("z"),
                .linkedLibrary("m")
            ]
        ),
        .target(
            name: "C2SF",
            path: "Sources/C2SF",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-I\(twoSFVendorDirectory)", "-I\(twoSFVendorDirectory)/desmume", "-I\(twoSFVendorDirectory)/sseqplayer"])
            ],
            linkerSettings: [
                .unsafeFlags(["\(twoSFBuildDirectory)/lib2sf.a"]),
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "CPlaybackAudio",
            path: "Sources/CPlaybackAudio",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CHighlyTheoretical",
            path: "Sources/CHighlyTheoretical",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags([
                    "-I\(highlyTheoreticalVendorDirectory)",
                    "-I\(rootPath)/vendor/psflib"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "\(highlyTheoreticalBuildDirectory)/libhighly_theoretical.a",
                    "\(lazyUSFBuildDirectory)/libpsflib.a"
                ]),
                .linkedLibrary("z"),
                .linkedLibrary("m")
            ]
        ),
        .target(
            name: "CVGMStream",
            path: "Sources/CVGMStream",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I\(vgmstreamVendorDirectory)"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "\(vgmstreamBuildDirectory)/src/libvgmstream.a",
                    "-L/opt/homebrew/opt/ffmpeg/lib",
                    "-L/opt/homebrew/opt/libvorbis/lib",
                    "-L/opt/homebrew/opt/libogg/lib"
                ]),
                .linkedLibrary("avcodec"),
                .linkedLibrary("avformat"),
                .linkedLibrary("avutil"),
                .linkedLibrary("swresample"),
                .linkedLibrary("vorbisfile"),
                .linkedLibrary("vorbis"),
                .linkedLibrary("ogg"),
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "CFFmpegAudio",
            path: "Sources/CFFmpegAudio",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/opt/ffmpeg/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/opt/ffmpeg/lib"]),
                .linkedLibrary("avcodec"),
                .linkedLibrary("avformat"),
                .linkedLibrary("avutil"),
                .linkedLibrary("swresample")
            ]
        ),
        .target(
            name: "CPlayPSF",
            path: "Sources/CPlayPSF",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-std=c++17",
                    "-I\(playPSFVendorDirectory)",
                    "-I\(rootPath)/vendor/play/Source",
                    "-I\(rootPath)/vendor/play/Source/app_shared",
                    "-I\(rootPath)/vendor/play/deps/CodeGen/src",
                    "-I\(rootPath)/vendor/play/deps/CodeGen/include",
                    "-I\(rootPath)/vendor/play/deps/Framework/include",
                    "-I\(rootPath)/vendor/play/deps/Dependencies/ghc_filesystem/include"
                ])
            ],
            linkerSettings: [
                .unsafeFlags(["\(playPSFBuildDirectory)/libcocoaspice_play_psf.a"]),
                .linkedLibrary("z"),
                .linkedLibrary("bz2")
            ]
        ),
        .executableTarget(
            name: "CocoaSpice",
            dependencies: ["CGME", "COpenMPT", "CLibVGM", "CHighlyComplete", "CHighlyTheoretical", "CLazyUSF", "C2SF", "CPlaybackAudio", "CVGMStream", "CFFmpegAudio", "CPlayPSF", .product(name: "MediaScannerKit", package: "MediaScanner")],
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
            dependencies: ["CocoaSpice", "C2SF"],
            resources: [
                .copy("cross-app-library-identity-v1.json"),
                .copy("cross-app-sidebar-search-view-v1.json"),
                .copy("cross-app-playlist-activation-v1.json"),
                .copy("cross-app-scanner-lifecycle-v1.json"),
                .copy("cross-app-scanner-policy-v1.json")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
