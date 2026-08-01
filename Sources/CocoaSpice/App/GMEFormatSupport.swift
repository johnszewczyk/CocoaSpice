import Foundation

enum PlaybackDecoderBackend: Hashable, Sendable {
    case gme
    case openMPT
    case standardAudio
    case libvgm
    case highlyComplete
    case highlyTheoretical
    case lazyUSF
    case twoSF
    case vgmstream
    case playPSF
}

enum ArchiveMaterializationPolicy: Equatable, Sendable {
    case selectedEntry
    case completeSet
    case completeSetWithLazyUSFAliases
}

struct PlaybackDecoderModule: Sendable {
    let pluginID: String
    let displayName: String
    let backend: PlaybackDecoderBackend
    let supportedExtensions: Set<String>
    let requiresTrackEnumeration: Bool
    let archiveMaterialization: ArchiveMaterializationPolicy
    /// Scanning can sometimes read an entry's container metadata without the
    /// sibling libraries that playback needs. Keep that optimization separate
    /// from the playback materialization contract.
    let scanArchiveMaterialization: ArchiveMaterializationPolicy
    let scanInspectionConcurrency: Int

    init(
        pluginID: String,
        displayName: String,
        backend: PlaybackDecoderBackend,
        supportedExtensions: Set<String>,
        requiresTrackEnumeration: Bool,
        archiveMaterialization: ArchiveMaterializationPolicy,
        scanArchiveMaterialization: ArchiveMaterializationPolicy? = nil,
        scanInspectionConcurrency: Int = 1
    ) {
        self.pluginID = pluginID
        self.displayName = displayName
        self.backend = backend
        self.supportedExtensions = supportedExtensions
        self.requiresTrackEnumeration = requiresTrackEnumeration
        self.archiveMaterialization = archiveMaterialization
        self.scanArchiveMaterialization = scanArchiveMaterialization ?? archiveMaterialization
        self.scanInspectionConcurrency = max(1, scanInspectionConcurrency)
    }

    var scanDescriptor: ScanPluginDescriptor {
        ScanPluginDescriptor(
            pluginID: pluginID,
            displayName: displayName,
            supportedExtensions: supportedExtensions,
            supportsMultiTrack: requiresTrackEnumeration,
            priority: 10
        )
    }
}

/// The one registry for extension-based admission, decoder routing, archive
/// dependency policy, scan concurrency, and multi-track behavior. Payload
/// recognizers for deliberately misnamed files are kept outside this table:
/// they run only after a supported container has been materialized.
enum PlaybackFormatRegistry {
    // Keep Long Play policy separate; these tables only define intake and decoder routing.
    static let libGMESupportedExtensions: Set<String> = [
        "ay",
        "gbs",
        "hes",
        "kss",
        "nsf",
        "nsfe",
        "sap",
        "spc"
    ]
    static let libGMEMultiTrackSupportedExtensions = libGMESupportedExtensions.subtracting(["spc"])
    private static let libGMEScanInspectionConcurrency = min(
        3,
        max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    )

    static let libVGMSupportedExtensions: Set<String> = [
        "gym",
        "s98",
        "vgm",
        "vgz"
    ]

    static let openMPTSupportedExtensions: Set<String> = ["xm"]

    // AVAudioFile provides the same streamed PCM and seek contract for these
    // containers. Keep them together so discovery, scanning, drag-and-drop,
    // and archive playback cannot drift apart.
    static let standardAudioSupportedExtensions: Set<String> = [
        "aif", "aiff", "flac", "m4a", "mp3", "wav"
    ]

    static let highlyCompleteSupportedExtensions: Set<String> = [
        "gsf",
        "minigsf"
    ]
    static let highlyTheoreticalSupportedExtensions: Set<String> = ["ssf", "minissf"]

    static let lazyUSFSupportedExtensions: Set<String> = [
        "usf",
        "miniusf"
    ]

    static let twoSFSupportedExtensions: Set<String> = [
        "2sf",
        "mini2sf"
    ]

    // vgmstream handles the PS2 rip families found in the Zophar collection,
    // plus 3DO's AIFC and GENH rips. Keep this list explicit so archive discovery and
    // deep scanning agree about what the backend can actually open.
    static let vgmstreamSupportedExtensions: Set<String> = [
        "aa3", "adx", "ads", "aifc", "at3", "aus", "bnk", "fsb", "genh", "int", "mib", "msf", "mtaf", "ogg", "rws", "ss2", "stream", "svag", "vag", "xa"
    ]
    static let psfSupportedExtensions: Set<String> = ["psf", "minipsf"]
    static let psf2SupportedExtensions: Set<String> = ["psf2", "minipsf2"]

    // Static modules are the current plugin boundary. A future dynamically loaded
    // module can provide the same extension and backend registration contract.
    static let modules: [PlaybackDecoderModule] = [
        PlaybackDecoderModule(
            pluginID: "gme", displayName: "Game Music Emu", backend: .gme,
            supportedExtensions: ["spc"],
            requiresTrackEnumeration: false, archiveMaterialization: .selectedEntry,
            scanInspectionConcurrency: libGMEScanInspectionConcurrency
        ),
        PlaybackDecoderModule(
            pluginID: "gme-multitrack", displayName: "Game Music Emu", backend: .gme,
            supportedExtensions: libGMEMultiTrackSupportedExtensions,
            requiresTrackEnumeration: true, archiveMaterialization: .selectedEntry,
            scanInspectionConcurrency: libGMEScanInspectionConcurrency
        ),
        PlaybackDecoderModule(
            pluginID: "openmpt", displayName: "libopenmpt", backend: .openMPT,
            supportedExtensions: openMPTSupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .selectedEntry
        ),
        PlaybackDecoderModule(
            pluginID: "standard-audio", displayName: "Core Audio", backend: .standardAudio,
            supportedExtensions: standardAudioSupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .selectedEntry
        ),
        PlaybackDecoderModule(
            pluginID: "libvgm", displayName: "libVGM", backend: .libvgm,
            supportedExtensions: libVGMSupportedExtensions,
            requiresTrackEnumeration: true, archiveMaterialization: .selectedEntry
        ),
        PlaybackDecoderModule(
            pluginID: "highly-complete", displayName: "Highly Complete", backend: .highlyComplete,
            supportedExtensions: highlyCompleteSupportedExtensions,
            requiresTrackEnumeration: true, archiveMaterialization: .completeSet
        ),
        PlaybackDecoderModule(
            pluginID: "highly-theoretical", displayName: "Highly Theoretical", backend: .highlyTheoretical,
            supportedExtensions: highlyTheoreticalSupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .completeSet,
            scanArchiveMaterialization: .selectedEntry
        ),
        PlaybackDecoderModule(
            pluginID: "lazyusf", displayName: "LazyUSF", backend: .lazyUSF,
            supportedExtensions: lazyUSFSupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .completeSetWithLazyUSFAliases,
            scanArchiveMaterialization: .selectedEntry
        ),
        PlaybackDecoderModule(
            pluginID: "twosf", displayName: "2SF", backend: .twoSF,
            supportedExtensions: twoSFSupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .completeSet,
            scanArchiveMaterialization: .selectedEntry
        ),
        PlaybackDecoderModule(
            pluginID: "vgmstream-hd-bank", displayName: "vgmstream", backend: .vgmstream,
            supportedExtensions: ["hd", "hbd", "iecs"],
            requiresTrackEnumeration: true, archiveMaterialization: .completeSet
        ),
        PlaybackDecoderModule(
            pluginID: "vgmstream-txtp", displayName: "vgmstream", backend: .vgmstream,
            supportedExtensions: ["txtp"],
            requiresTrackEnumeration: true, archiveMaterialization: .completeSet
        ),
        PlaybackDecoderModule(
            pluginID: "vgmstream", displayName: "vgmstream", backend: .vgmstream,
            supportedExtensions: vgmstreamSupportedExtensions,
            requiresTrackEnumeration: true, archiveMaterialization: .selectedEntry
        ),
        PlaybackDecoderModule(
            pluginID: "play-psf1", displayName: "Play! PSF", backend: .playPSF,
            supportedExtensions: psfSupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .completeSet,
            scanArchiveMaterialization: .selectedEntry
        ),
        PlaybackDecoderModule(
            pluginID: "play-psf2", displayName: "Play! PSF2", backend: .playPSF,
            supportedExtensions: psf2SupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .completeSet,
            scanArchiveMaterialization: .selectedEntry
        )
    ]

    static let supportedExtensions: Set<String> = Set(modules.flatMap(\.supportedExtensions))
    static let scanPluginDescriptors = modules.map(\.scanDescriptor)

    static func admits(pathExtension: String) -> Bool {
        supportedExtensions.contains(normalize(pathExtension))
    }

    static func admits(fileURL: URL) -> Bool {
        admits(pathExtension: fileURL.pathExtension)
    }

    static func module(forPathExtension extensionName: String) -> PlaybackDecoderModule? {
        let normalized = normalize(extensionName)
        return modules.first { $0.supportedExtensions.contains(normalized) }
    }

    static func archiveMaterializationForInspection(
        entryPaths: [String]
    ) -> ArchiveMaterializationPolicy? {
        guard !entryPaths.isEmpty else { return nil }
        var resolved = ArchiveMaterializationPolicy.selectedEntry
        for entryPath in entryPaths {
            guard let module = module(
                forPathExtension: URL(fileURLWithPath: entryPath).pathExtension
            ) else {
                return nil
            }
            switch module.archiveMaterialization {
            case .selectedEntry:
                break
            case .completeSet:
                if resolved == .selectedEntry { resolved = .completeSet }
            case .completeSetWithLazyUSFAliases:
                resolved = .completeSetWithLazyUSFAliases
            }
        }
        return resolved
    }

    static func scanArchiveMaterializationForInspection(
        entryPaths: [String]
    ) -> ArchiveMaterializationPolicy? {
        guard !entryPaths.isEmpty else { return nil }
        var resolved = ArchiveMaterializationPolicy.selectedEntry
        for entryPath in entryPaths {
            guard let module = module(
                forPathExtension: URL(fileURLWithPath: entryPath).pathExtension
            ) else {
                return nil
            }
            switch module.scanArchiveMaterialization {
            case .selectedEntry:
                break
            case .completeSet:
                if resolved == .selectedEntry { resolved = .completeSet }
            case .completeSetWithLazyUSFAliases:
                resolved = .completeSetWithLazyUSFAliases
            }
        }
        return resolved
    }

    static func playbackBackend(forPathExtension extensionName: String) -> PlaybackDecoderBackend? {
        module(forPathExtension: extensionName)?.backend
    }

    static func requiresTrackEnumeration(forPathExtension extensionName: String) -> Bool {
        module(forPathExtension: extensionName)?.requiresTrackEnumeration ?? false
    }

    private static func normalize(_ pathExtension: String) -> String {
        pathExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
    }
}
