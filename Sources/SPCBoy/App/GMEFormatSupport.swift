import Foundation

enum PlaybackDecoderBackend: Sendable {
    case gme
    case libvgm
    case highlyComplete
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

    static let supportedExtensions: Set<String> =
        libGMESupportedExtensions
        .union(libVGMSupportedExtensions)
        .union(highlyCompleteSupportedExtensions)

    static func playbackBackend(forPathExtension extensionName: String) -> PlaybackDecoderBackend? {
        let normalized = extensionName.lowercased()
        if highlyCompleteSupportedExtensions.contains(normalized) {
            return .highlyComplete
        }
        if libVGMSupportedExtensions.contains(normalized) {
            return .libvgm
        }
        if libGMESupportedExtensions.contains(normalized) {
            return .gme
        }
        return nil
    }
}
