import Foundation
import ArchiveMaterializationCore
import VGMBoyKit

/// CocoaSpice asks VGMBoyKit which files it can play. The only local policy is
/// how an archive is materialized before a playable file path is handed over.
enum PlaybackFormatRegistry {
    static let supportedExtensions: Set<String> =
        FormatRegistry.libgmeExtensions
        .union(FormatRegistry.libvgmExtensions)
        .union(FormatRegistry.sidplayfpExtensions)
        .union(FormatRegistry.standardAudioExtensions)
        .union(FormatRegistry.highlyCompleteExtensions)
        .union(FormatRegistry.twoSFExtensions)
        .union(FormatRegistry.vgmstreamExtensions)
        .union(FormatRegistry.lazyusfExtensions)
        .union(FormatRegistry.playpsfExtensions)

    private static let completeSetExtensions: Set<String> =
        FormatRegistry.highlyCompleteExtensions
        .union(FormatRegistry.twoSFExtensions)
        .union(["hd", "hbd", "iecs", "txtp"])
        .union(FormatRegistry.playpsfExtensions)

    static func admits(fileURL: URL) -> Bool {
        admits(pathExtension: fileURL.pathExtension)
    }

    static func admits(pathExtension: String) -> Bool {
        supportedExtensions.contains(normalize(pathExtension))
    }

    static func supportsLongPlay(pathExtension: String) -> Bool {
        FormatRegistry.family(for: "source.\(normalize(pathExtension))")?.supportsLongPlay ?? false
    }

    static func archiveMaterialization(for entryPaths: [String]) -> ArchiveMaterializationPlan? {
        guard !entryPaths.isEmpty else { return nil }
        var resolved: ArchiveMaterializationPlan = .selectedEntry
        for entryPath in entryPaths {
            let extensionName = normalize(URL(fileURLWithPath: entryPath).pathExtension)
            guard admits(pathExtension: extensionName) else { return nil }
            if FormatRegistry.lazyusfExtensions.contains(extensionName) {
                resolved = .completeSetWithLazyUSFAliases
            } else if completeSetExtensions.contains(extensionName), resolved == .selectedEntry {
                resolved = .completeSet
            }
        }
        return resolved
    }

    private static func normalize(_ pathExtension: String) -> String {
        pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
    }
}
