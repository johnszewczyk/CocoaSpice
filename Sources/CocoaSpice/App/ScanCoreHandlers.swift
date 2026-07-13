import Foundation

/// Metadata-only bridge to the installed decoder cores. This creates an
/// inspector, never a playback session, and keeps the scanner's plugin route
/// independent from the playback transport layer.
struct DecoderCoreScanHandler: ScanFormatHandler {
    let descriptor: ScanPluginDescriptor

    private static let inspectionGate = ScanResourceScheduler(permits: 1)

    func inspect(fileURL: URL, route: ScanRoute) async throws -> ScanInspection {
        // SPC metadata lives in a fixed header. Avoid opening libgme for every
        // 64 KiB SPC member during a library scan.
        if route.formatExtension == "spc" {
            return ScanInspection(
                route: route,
                tracks: [ScanTrackMetadata(
                    trackIndex: 0,
                    trackCount: 1,
                    metadata: SPCHeaderMetadata.read(from: fileURL)
                )]
            )
        }
        let tracks = try await Self.inspectionGate.withPermit {
            try await Task.detached(priority: .utility) {
                let inspector = try PlaybackDecoderFactory.makeInspector(fileURL: fileURL)
                let trackCount = max(1, inspector.trackCount)
                return try (0..<trackCount).map { index in
                    ScanTrackMetadata(
                        trackIndex: index,
                        trackCount: trackCount,
                        metadata: try inspector.metadata(trackIndex: index)
                    )
                }
            }.value
        }
        return ScanInspection(route: route, tracks: tracks)
    }
}

enum ScanCoreHandlers {
    static let registry = ScanPluginRegistry(descriptors: [
        ScanPluginDescriptor(
            pluginID: "gme",
            displayName: "Game Music Emu",
            supportedExtensions: GMEFormatSupport.libGMESupportedExtensions,
            supportsMultiTrack: true,
            priority: 10
        ),
        ScanPluginDescriptor(
            pluginID: "libvgm",
            displayName: "libVGM",
            supportedExtensions: GMEFormatSupport.libVGMSupportedExtensions,
            supportsMultiTrack: true,
            priority: 10
        ),
        ScanPluginDescriptor(
            pluginID: "highly-complete",
            displayName: "Highly Complete",
            supportedExtensions: GMEFormatSupport.highlyCompleteSupportedExtensions,
            supportsMultiTrack: true,
            priority: 10
        ),
        ScanPluginDescriptor(
            pluginID: "lazyusf",
            displayName: "LazyUSF",
            supportedExtensions: GMEFormatSupport.lazyUSFSupportedExtensions,
            supportsMultiTrack: true,
            priority: 10
        ),
        ScanPluginDescriptor(
            pluginID: "twosf",
            displayName: "2SF",
            supportedExtensions: GMEFormatSupport.twoSFSupportedExtensions,
            supportsMultiTrack: false,
            priority: 10
        )
    ])

    static let handlers = ScanPluginHandlerRegistry(handlers: [
        DecoderCoreScanHandler(descriptor: registryDescriptor("gme")),
        DecoderCoreScanHandler(descriptor: registryDescriptor("libvgm")),
        DecoderCoreScanHandler(descriptor: registryDescriptor("highly-complete")),
        DecoderCoreScanHandler(descriptor: registryDescriptor("lazyusf")),
        DecoderCoreScanHandler(descriptor: registryDescriptor("twosf"))
    ])

    private static func registryDescriptor(_ pluginID: String) -> ScanPluginDescriptor {
        // The handler descriptors are kept in one registry above so adding a
        // plugin requires one descriptor and one handler, not scanner changes.
        switch pluginID {
        case "gme":
            return ScanPluginDescriptor(
                pluginID: "gme",
                displayName: "Game Music Emu",
                supportedExtensions: GMEFormatSupport.libGMESupportedExtensions,
                supportsMultiTrack: true,
                priority: 10
            )
        case "libvgm":
            return ScanPluginDescriptor(
                pluginID: "libvgm",
                displayName: "libVGM",
                supportedExtensions: GMEFormatSupport.libVGMSupportedExtensions,
                supportsMultiTrack: true,
                priority: 10
            )
        case "highly-complete":
            return ScanPluginDescriptor(
                pluginID: "highly-complete",
                displayName: "Highly Complete",
                supportedExtensions: GMEFormatSupport.highlyCompleteSupportedExtensions,
                supportsMultiTrack: true,
                priority: 10
            )
        case "twosf":
            return ScanPluginDescriptor(
                pluginID: "twosf",
                displayName: "2SF",
                supportedExtensions: GMEFormatSupport.twoSFSupportedExtensions,
                supportsMultiTrack: false,
                priority: 10
            )
        default:
            return ScanPluginDescriptor(
                pluginID: "lazyusf",
                displayName: "LazyUSF",
                supportedExtensions: GMEFormatSupport.lazyUSFSupportedExtensions,
                supportsMultiTrack: true,
                priority: 10
            )
        }
    }
}
