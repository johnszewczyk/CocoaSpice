import Foundation

/// Resolves the console used by the Database sidebar. Decoder selection is a
/// playback concern: a container such as GENH can legitimately occur under
/// several consoles, so it cannot by itself identify a library console.
enum LibraryConsoleResolver {
    private static let knownConsoleNames = [
        "3DO", "FM Towns", "Microsoft MSX", "NEC PC Engine", "NEC PC-98", "NEC PC-FX",
        "Nintendo 64", "Nintendo DS", "Nintendo Game Boy", "Nintendo Game Boy Advance",
        "Nintendo NES", "Nintendo SNES", "PC", "SNK Neo Geo CD", "Sega 32X", "Sega CD",
        "Sega Game Gear", "Sega Genesis", "Sega Master System", "Sega Pico", "Sega Saturn",
        "Sony PSP", "Sony PlayStation", "Sony PlayStation 2", "Sony PlayStation 3"
    ]

    private static let canonicalConsoleNames = Dictionary(
        uniqueKeysWithValues: knownConsoleNames.map { ($0.lowercased(), $0) }
    )

    static func browserSystem(
        metadataSystem: String,
        route: ScanRoute,
        sourcePath: String,
        rootPath: String?
    ) -> String {
        let taggedSystem = metadataSystem.trimmingCharacters(in: .whitespacesAndNewlines)

        // vgmstream supplies a decoder-family default, not a console tag. In
        // particular, GENH is a header format used by rips from many systems.
        if route.pluginID == "vgmstream", let folderSystem = consoleFolder(for: sourcePath, rootPath: rootPath) {
            return folderSystem
        }

        return taggedSystem.nonEmpty ?? consoleFolder(for: sourcePath, rootPath: rootPath) ?? ""
    }

    static func consoleFolder(for sourcePath: String, rootPath: String?) -> String? {
        let sourceDirectory = URL(fileURLWithPath: sourcePath, isDirectory: false)
            .deletingLastPathComponent()
            .standardizedFileURL
        let components: [String]

        if let rootPath {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
            let rootPrefix = root.path == "/" ? "/" : root.path + "/"
            guard sourceDirectory.path == root.path || sourceDirectory.path.hasPrefix(rootPrefix) else {
                return nil
            }
            let relative = sourceDirectory.path.dropFirst(root.path.count)
            components = relative.split(separator: "/").map(String.init)
            if let rootConsole = canonicalConsoleNames[root.lastPathComponent.lowercased()] {
                return rootConsole
            }
        } else {
            components = sourceDirectory.pathComponents
        }

        // Work upward so an intervening format folder (KSS, VGM, VGZ, etc.)
        // never masks a console folder.
        return components.reversed().lazy.compactMap {
            canonicalConsoleNames[$0.lowercased()]
        }.first
    }
}
