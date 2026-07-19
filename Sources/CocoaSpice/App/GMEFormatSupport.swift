import Foundation

enum PlaybackDecoderBackend: Sendable {
    case gme
    case libvgm
    case highlyComplete
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

enum GMEFormatSupport {
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

    static let libVGMSupportedExtensions: Set<String> = [
        "gym",
        "s98",
        "vgm",
        "vgz"
    ]

    static let highlyCompleteSupportedExtensions: Set<String> = [
        "gsf",
        "minigsf"
    ]

    static let lazyUSFSupportedExtensions: Set<String> = [
        "usf",
        "miniusf"
    ]

    static let twoSFSupportedExtensions: Set<String> = [
        "2sf",
        "mini2sf"
    ]

    // vgmstream handles the PS2 rip families found in the Zophar collection,
    // not only SVAG/IECS. Keep this list explicit so archive discovery and
    // deep scanning agree about what the backend can actually open.
    static let vgmstreamSupportedExtensions: Set<String> = [
        "adx", "ads", "aus", "hd", "hbd", "iecs", "int", "mib", "mtaf", "rws", "ss2", "svag", "vag", "xa"
    ]
    static let psfSupportedExtensions: Set<String> = ["psf", "minipsf"]
    static let psf2SupportedExtensions: Set<String> = ["psf2", "minipsf2"]

    // Static modules are the current plugin boundary. A future dynamically loaded
    // module can provide the same extension and backend registration contract.
    static let modules: [PlaybackDecoderModule] = [
        PlaybackDecoderModule(
            pluginID: "gme", displayName: "Game Music Emu", backend: .gme,
            supportedExtensions: libGMESupportedExtensions,
            requiresTrackEnumeration: true, archiveMaterialization: .selectedEntry
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
            pluginID: "lazyusf", displayName: "LazyUSF", backend: .lazyUSF,
            supportedExtensions: lazyUSFSupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .completeSetWithLazyUSFAliases
        ),
        PlaybackDecoderModule(
            pluginID: "twosf", displayName: "2SF", backend: .twoSF,
            supportedExtensions: twoSFSupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .completeSet
        ),
        PlaybackDecoderModule(
            pluginID: "vgmstream", displayName: "vgmstream", backend: .vgmstream,
            supportedExtensions: vgmstreamSupportedExtensions,
            requiresTrackEnumeration: true, archiveMaterialization: .selectedEntry
        ),
        PlaybackDecoderModule(
            pluginID: "play-psf1", displayName: "Play! PSF", backend: .playPSF,
            supportedExtensions: psfSupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .completeSet
        ),
        PlaybackDecoderModule(
            pluginID: "play-psf2", displayName: "Play! PSF2", backend: .playPSF,
            supportedExtensions: psf2SupportedExtensions,
            requiresTrackEnumeration: false, archiveMaterialization: .completeSet
        )
    ]

    static let supportedExtensions: Set<String> = Set(modules.flatMap(\.supportedExtensions))
    static let scanPluginDescriptors = modules.map(\.scanDescriptor)

    static func module(forPathExtension extensionName: String) -> PlaybackDecoderModule? {
        let normalized = extensionName.lowercased()
        return modules.first { $0.supportedExtensions.contains(normalized) }
    }

    static func playbackBackend(forPathExtension extensionName: String) -> PlaybackDecoderBackend? {
        module(forPathExtension: extensionName)?.backend
    }

    static func requiresTrackEnumeration(forPathExtension extensionName: String) -> Bool {
        module(forPathExtension: extensionName)?.requiresTrackEnumeration ?? false
    }
}
