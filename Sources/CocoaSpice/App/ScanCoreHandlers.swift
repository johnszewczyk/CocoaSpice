import Foundation

/// Metadata-only bridge to the installed decoder cores. This creates an
/// inspector, never a playback session, and keeps the scanner's plugin route
/// independent from the playback transport layer.
struct DecoderCoreScanHandler: ScanFormatHandler {
    let descriptor: ScanPluginDescriptor

    private static let inspectionGate = ScanResourceScheduler(permits: 1)

    func inspect(fileURL: URL, route: ScanRoute) async throws -> ScanInspection {
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
    static let registry = ScanPluginRegistry(
        descriptors: GMEFormatSupport.scanPluginDescriptors
    )

    static let handlers = ScanPluginHandlerRegistry(
        handlers: GMEFormatSupport.scanPluginDescriptors.map {
            DecoderCoreScanHandler(descriptor: $0) as any ScanFormatHandler
        }
    )
}
