import Foundation

/// Metadata-only bridge to the installed decoder cores. This creates an
/// inspector, never a playback session, and keeps the scanner's plugin route
/// independent from the playback transport layer.
struct DecoderCoreScanHandler: ScanFormatHandler {
    let descriptor: ScanPluginDescriptor
    let inspectionGate: ScanResourceScheduler

    init(
        descriptor: ScanPluginDescriptor,
        inspectionGate: ScanResourceScheduler = ScanResourceScheduler(permits: 1)
    ) {
        self.descriptor = descriptor
        self.inspectionGate = inspectionGate
    }

    func inspect(fileURL: URL, route: ScanRoute) async throws -> ScanInspection {
        let tracks = try await inspectionGate.withPermit {
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

/// SPC exposes its ID666/xID6 metadata without needing libgme to initialize a
/// decoder. Keep libgme as the fallback for valid but unusual SPC variants.
struct SPCMetadataScanHandler: ScanFormatHandler {
    let descriptor: ScanPluginDescriptor
    let fallback: DecoderCoreScanHandler

    func inspect(fileURL: URL, route: ScanRoute) async throws -> ScanInspection {
        if let metadata = try await Task.detached(priority: .utility, operation: {
            try SPCMetadataReader.read(fileURL: fileURL)
        }).value {
            return ScanInspection(
                route: route,
                tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)]
            )
        }
        return try await fallback.inspect(fileURL: fileURL, route: route)
    }
}

enum ScanCoreHandlers {
    static let registry = ScanPluginRegistry(
        descriptors: GMEFormatSupport.scanPluginDescriptors
    )

    static let handlers: ScanPluginHandlerRegistry = {
        var schedulers: [PlaybackDecoderBackend: ScanResourceScheduler] = [:]
        let handlers: [any ScanFormatHandler] = GMEFormatSupport.modules.map { module in
            let scheduler: ScanResourceScheduler
            if let existing = schedulers[module.backend] {
                scheduler = existing
            } else {
                scheduler = ScanResourceScheduler(permits: module.scanInspectionConcurrency)
                schedulers[module.backend] = scheduler
            }
            let decoderHandler = DecoderCoreScanHandler(
                descriptor: module.scanDescriptor,
                inspectionGate: scheduler
            )
            if module.pluginID == "gme" {
                return SPCMetadataScanHandler(
                    descriptor: module.scanDescriptor,
                    fallback: decoderHandler
                )
            }
            return decoderHandler
        }
        return ScanPluginHandlerRegistry(handlers: handlers)
    }()
}
