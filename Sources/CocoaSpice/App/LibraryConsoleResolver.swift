import Foundation

/// Resolves the console used by the Database sidebar. Decoder selection is a
/// playback concern: a container such as GENH can legitimately occur under
/// several consoles, so it cannot by itself identify a library console.
enum LibraryConsoleResolver {
    private static let knownConsoleNames = [
        "3DO", "FM Towns", "Microsoft MSX", "NEC PC Engine", "NEC PC-98", "NEC PC-FX",
        "Nintendo 64", "Nintendo DS", "Nintendo Game Boy", "Nintendo Game Boy Advance",
        "Nintendo Entertainment System", "Super Nintendo", "PC", "SNK Neo Geo CD", "Sega 32X", "Sega CD",
        "Sega Game Gear", "Sega Genesis", "Sega Master System", "Sega Pico", "Sega Saturn",
        "Sony PSP", "Sony PlayStation", "Sony PlayStation 2", "Sony PlayStation 3"
    ]

    /// Filename tags are collection identity, not decoder metadata. Keep this
    /// vocabulary in step with SPCBoy's executable conformance fixture.
    private static let consoleTagNames = [
        "PS1": "Sony PlayStation", "PSX": "Sony PlayStation", "PS2": "Sony PlayStation 2",
        "PS3": "Sony PlayStation 3", "PSP": "Sony PSP", "PSV": "Sony PlayStation Vita",
        "NDS": "Nintendo DS", "DS": "Nintendo DS", "3DS": "Nintendo 3DS",
        "GBA": "Nintendo Game Boy Advance", "GBC": "Nintendo Game Boy Color", "GB": "Nintendo Game Boy",
        "N64": "Nintendo 64", "NES": "Nintendo Entertainment System", "SNES": "Super Nintendo",
        "GC": "Nintendo GameCube", "WII": "Nintendo Wii", "WIIU": "Nintendo Wii U",
        "SWITCH": "Nintendo Switch", "MD": "Sega Mega Drive", "GEN": "Sega Genesis",
        "SMS": "Sega Master System", "SAT": "Sega Saturn", "DC": "Sega Dreamcast",
        "GG": "Sega Game Gear", "PCE": "NEC PC Engine", "TG16": "NEC TurboGrafx-16",
        "PCFX": "NEC PC-FX", "XBOX": "Microsoft Xbox", "X360": "Microsoft Xbox 360",
        "XONE": "Microsoft Xbox One", "PC98": "NEC PC-98", "FMT": "FM Towns",
        "3DO": "3DO", "ARC": "Arcade"
    ]

    private static let canonicalConsoleNames: [String: String] = {
        var names = Dictionary(uniqueKeysWithValues: knownConsoleNames.map { ($0.lowercased(), $0) })
        for (tag, console) in consoleTagNames {
            names[tag.lowercased()] = console
            names[console.lowercased()] = console
        }
        names.merge([
            "playstation": "Sony PlayStation",
            "playstation 2": "Sony PlayStation 2",
            "playstation 3": "Sony PlayStation 3",
            "sony playstation 4": "Sony PlayStation 4",
            "sony playstation 5": "Sony PlayStation 5",
            "nintendo nes": "Nintendo Entertainment System",
            "nintendo snes": "Super Nintendo"
        ]) { _, replacement in replacement }
        return names
    }()

    static func browserGame(metadataGame: String, sourcePath: String, archiveEntry: String?) -> String {
        let taggedGame = metadataGame.trimmingCharacters(in: .whitespacesAndNewlines)
        if let taggedGame = taggedGame.nonEmpty { return taggedGame }
        let sourceURL = URL(fileURLWithPath: sourcePath, isDirectory: false)
        if archiveEntry != nil {
            return collectionTitle(from: sourceURL.lastPathComponent)
        }
        return sourceURL.deletingLastPathComponent().lastPathComponent.nonEmpty
            ?? collectionTitle(from: sourceURL.lastPathComponent)
    }

    static func browserSystem(
        metadataSystem: String,
        route: ScanRoute?,
        sourcePath: String,
        rootPath: String?,
        preferEmbeddedMetadata: Bool = false
    ) -> String {
        let taggedSystem = canonicalConsoleName(
            metadataSystem.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let filenameSystem = consoleFromSourceTag(sourcePath)
        let folderSystem = consoleFolder(for: sourcePath, rootPath: rootPath)
        let collectionSystem = filenameSystem ?? folderSystem

        // vgmstream supplies a decoder-family default, not a console tag. In
        // particular, GENH is a header format used by rips from many systems.
        if !preferEmbeddedMetadata, route?.pluginID == "vgmstream", let collectionSystem {
            return collectionSystem
        }

        return preferEmbeddedMetadata
            ? taggedSystem ?? collectionSystem ?? ""
            : collectionSystem ?? taggedSystem ?? ""
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

    private static func canonicalConsoleName(_ value: String) -> String? {
        guard let value = value.nonEmpty else { return nil }
        return canonicalConsoleNames[value.lowercased()] ?? value
    }

    private static func consoleFromSourceTag(_ sourcePath: String) -> String? {
        let filename = URL(fileURLWithPath: sourcePath, isDirectory: false).lastPathComponent
        var searchEnd = filename.endIndex
        while let close = filename[..<searchEnd].lastIndex(of: "]"),
              let open = filename[..<close].lastIndex(of: "[") {
            let tag = filename[filename.index(after: open)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if let console = consoleTagNames[tag] { return console }
            searchEnd = open
        }
        return nil
    }

    private static func collectionTitle(from filename: String) -> String {
        let title = FilenamePresentation.withoutDisplayedExtension(filename)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.last == "]", let open = title.lastIndex(of: "[") else { return title }
        let tag = title[title.index(after: open)..<title.index(before: title.endIndex)]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard consoleTagNames[tag] != nil else { return title }
        return title[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
