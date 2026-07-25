import Foundation

/// The scanner's one registry for safe metadata-only format shortcuts.
///
/// A rule may return metadata only when the format exposes it without
/// starting an emulation/decoder core. Every rule receives the normal decoder
/// handler as its fallback, so adding a new format never changes the general
/// scan contract or creates a parallel scan path.
enum ScanMetadataShortcuts {
    static func handler(
        for module: PlaybackDecoderModule,
        fallback: DecoderCoreScanHandler
    ) -> any ScanFormatHandler {
        switch module.pluginID {
        case "gme":
            return SPCMetadataScanHandler(
                descriptor: module.scanDescriptor,
                fallback: fallback
            )
        case "libvgm":
            return VGMMetadataScanHandler(
                descriptor: module.scanDescriptor,
                fallback: fallback
            )
        case "lazyusf", "twosf", "play-psf1", "play-psf2":
            return PSFMetadataScanHandler(
                descriptor: module.scanDescriptor,
                fallback: fallback
            )
        default:
            return fallback
        }
    }
}
