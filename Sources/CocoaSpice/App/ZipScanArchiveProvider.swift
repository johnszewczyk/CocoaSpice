import Foundation

struct ZipScanArchiveProvider: ScanArchiveProvider {
    let registry: ScanPluginRegistry
    let scheduler: ScanResourceScheduler

    init(
        registry: ScanPluginRegistry,
        scheduler: ScanResourceScheduler = ScanResourceScheduler(
            permits: max(1, ProcessInfo.processInfo.activeProcessorCount)
        )
    ) {
        self.registry = registry
        self.scheduler = scheduler
    }

    func listMembers(
        in archiveURL: URL,
        supportedExtensions: Set<String>
    ) async throws -> ScanArchiveListing {
        try await scheduler.withPermit {
            let listing = try ZipArchiveSupport.listPlayableEntryListing(
                in: archiveURL,
                supportedExtensions: supportedExtensions
            )
            let fingerprint = Self.fingerprint(for: archiveURL)
            let members: [ScanArchiveMember] = listing.entries.compactMap { entry in
                let route = registry.route(
                    for: URL(fileURLWithPath: entry.entryPath).pathExtension,
                    archiveMember: true
                )
                guard let route else { return nil }
                return ScanArchiveMember(
                    archiveURL: entry.archiveURL,
                    entryPath: entry.entryPath,
                    fingerprint: fingerprint,
                    route: route
                )
            }
            return ScanArchiveListing(
                members: members,
                scanSignature: listing.scanSignature
            )
        }
    }

    func materialize(archiveURL: URL, entryPath: String) async throws -> URL {
        try await scheduler.withPermit {
            try ZipArchiveSupport.materializeEntry(
                archiveURL: archiveURL,
                entryPath: entryPath
            )
        }
    }

    func materializeEntries(archiveURL: URL, entryPaths: [String]) async throws -> URL {
        try await scheduler.withPermit {
            try ZipArchiveSupport.materializeEntries(
                at: archiveURL,
                entryPaths: entryPaths
            )
        }
    }

    func materializeArchive(at archiveURL: URL) async throws -> URL {
        try await scheduler.withPermit {
            try ZipArchiveSupport.materializeArchive(at: archiveURL)
        }
    }

    func materializeEntriesForScan(archiveURL: URL, entryPaths: [String]) async throws -> URL {
        try await scheduler.withPermit {
            try ZipArchiveSupport.materializeEntriesForScan(
                at: archiveURL,
                entryPaths: entryPaths
            )
        }
    }

    func materializeArchiveForScan(at archiveURL: URL) async throws -> URL {
        try await scheduler.withPermit {
            try ZipArchiveSupport.materializeArchiveForScan(at: archiveURL)
        }
    }

    func discardScanMaterialization(at rootURL: URL) async {
        ZipArchiveSupport.discardScanMaterialization(at: rootURL)
    }

    private static func fingerprint(for url: URL) -> ScanFingerprint {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ScanFingerprint(
            fileSize: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate ?? .distantPast
        )
    }
}
