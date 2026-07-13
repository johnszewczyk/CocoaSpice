import Foundation

enum PlaybackDecoderBackend: Sendable {
    case gme
    case libvgm
    case highlyComplete
    case lazyUSF
    case twoSF
}

struct PlaybackDecoderModule: Sendable {
    let backend: PlaybackDecoderBackend
    let supportedExtensions: Set<String>
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

    // Static modules are the current plugin boundary. A future dynamically loaded
    // module can provide the same extension and backend registration contract.
    static let modules: [PlaybackDecoderModule] = [
        PlaybackDecoderModule(backend: .gme, supportedExtensions: libGMESupportedExtensions),
        PlaybackDecoderModule(backend: .libvgm, supportedExtensions: libVGMSupportedExtensions),
        PlaybackDecoderModule(backend: .highlyComplete, supportedExtensions: highlyCompleteSupportedExtensions),
        PlaybackDecoderModule(backend: .lazyUSF, supportedExtensions: lazyUSFSupportedExtensions),
        PlaybackDecoderModule(backend: .twoSF, supportedExtensions: twoSFSupportedExtensions)
    ]

    static let supportedExtensions: Set<String> = Set(modules.flatMap(\.supportedExtensions))

    static func playbackBackend(forPathExtension extensionName: String) -> PlaybackDecoderBackend? {
        let normalized = extensionName.lowercased()
        return modules.first { $0.supportedExtensions.contains(normalized) }?.backend
    }
}
