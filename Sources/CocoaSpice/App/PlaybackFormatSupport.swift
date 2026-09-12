import Foundation
import ArchiveMaterializationCore
import VGMBoyFormatCore
import VGMBoyKit

/// CocoaSpice asks VGMBoyKit which files it can play. The only local policy is
/// how an archive is materialized before a playable file path is handed over.
enum PlaybackFormatRegistry {
    static let supportedExtensions: Set<String> = FormatRegistry.playbackExtensions

    static func admits(fileURL: URL) -> Bool {
        admits(path: fileURL.path)
    }

    static func admits(path: String) -> Bool {
        FormatRegistry.descriptor(for: path) != nil
    }

    static func admitsAmigaPrefix(path: String) -> Bool {
        FormatRegistry.descriptor(for: path)?.id == "amiga-uade"
    }

    static func admits(pathExtension: String) -> Bool {
        supportedExtensions.contains(normalize(pathExtension))
    }

    static func supportsLongPlay(pathExtension: String) -> Bool {
        FormatRegistry.descriptor(for: "source.\(normalize(pathExtension))")?.supportsLongPlay ?? false
    }

    static func archiveMaterialization(for entryPaths: [String]) -> VGMArchiveMaterializationRequirement? {
        guard !entryPaths.isEmpty else { return nil }
        guard entryPaths.allSatisfy({ admits(path: $0) }) else {
            return nil
        }
        return FormatRegistry.archiveMaterializationRequirement(for: entryPaths)
    }

    private static func normalize(_ pathExtension: String) -> String {
        pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
    }
}
