import Foundation
import MediaScannerKit

enum ScanFilesystemDiscovery {
    static func discover(
        rootID: Int64,
        rootURL: URL,
        registry: ScanPluginRegistry
    ) async throws -> [ScanCandidate] {
        try await MediaScannerKit.ScanFilesystemDiscovery.discover(
            rootID: rootID,
            rootURL: rootURL,
            registry: registry,
            isArchive: { ZipArchiveSupport.canHandle($0) }
        )
    }
}
