import Foundation

struct ScanCandidate: Hashable, Sendable {
    let identity: ScanItemIdentity
    let fingerprint: ScanFingerprint
    let sourceURL: URL
    let route: ScanRoute?

    var isArchiveMember: Bool {
        identity.archiveEntry != nil
    }
}

struct ScanArchiveMember: Hashable, Sendable {
    let archiveURL: URL
    let entryPath: String
    let fingerprint: ScanFingerprint
    let route: ScanRoute?

    var identityDescription: String {
        "\(archiveURL.path)#\(entryPath)"
    }
}

struct ScanArchiveListing: Sendable {
    let members: [ScanArchiveMember]
    /// The archive tool's own report, when the listing operation provides it.
    let scanSignature: String?
}

struct ScanTrackMetadata: Sendable {
    let trackIndex: Int
    let trackCount: Int
    let metadata: TrackMetadata?
}

struct ScanInspection: Sendable {
    let route: ScanRoute
    let tracks: [ScanTrackMetadata]
}

enum ArchiveScanDepth: Sendable, Equatable {
    case fast
    case deep
}

enum FastScanPlaceholder {
    static let metadataComment = "__cocoaspice_fast_scan__"
}

enum ScanFailureStage: String, Sendable {
    case discovery
    case archiveListing
    case archiveExtraction
    case routing
    case metadata
    case persistence
}

struct ScanFailure: Sendable {
    let identity: ScanItemIdentity
    let fingerprint: ScanFingerprint
    let route: ScanRoute?
    let stage: ScanFailureStage
    let message: String
}

enum ScanPipelineResult: Sendable {
    case success(ScanCandidate, ScanInspection)
    /// A deep archive scan completed every discovered member successfully.
    /// This parent inventory item is the incremental-scan skip gate; it does
    /// not create a synthetic playlist track.
    case archiveCompleted(ScanCandidate)
    case unsupported(ScanCandidate)
    case failure(ScanFailure)
}

extension ScanPipelineResult {
    func persistenceFailure(message: String) -> ScanPipelineResult {
        let failure: ScanFailure
        switch self {
        case .success(let candidate, _), .unsupported(let candidate):
            failure = ScanFailure(
                identity: candidate.identity,
                fingerprint: candidate.fingerprint,
                route: candidate.route,
                stage: .persistence,
                message: message
            )
        case .archiveCompleted(let candidate):
            failure = ScanFailure(
                identity: candidate.identity,
                fingerprint: candidate.fingerprint,
                route: candidate.route,
                stage: .persistence,
                message: message
            )
        case .failure(let existing):
            failure = ScanFailure(
                identity: existing.identity,
                fingerprint: existing.fingerprint,
                route: existing.route,
                stage: .persistence,
                message: message
            )
        }
        return .failure(failure)
    }
}

struct ScanPlan: Sendable {
    let mode: ScanMode
    let candidates: [ScanCandidate]

    var count: Int { candidates.count }
}

struct ScanSummary: Sendable {
    let discovered: Int
    let completed: Int
    let successful: Int
    let failed: Int
    let unsupported: Int
    let cancelled: Int
    let failures: [ScanFailure]
}

actor ScanResultAccumulator: ScanResultSink {
    private var discoveredCount = 0
    private var completedCount = 0
    private var successfulCount = 0
    private var failedCount = 0
    private var unsupportedCount = 0
    private var cancelledCount = 0
    private var failureValues: [ScanFailure] = []
    private var resultValues: [ScanPipelineResult] = []

    init(discovered: Int = 0) {
        discoveredCount = discovered
    }

    func accept(_ result: ScanPipelineResult) async throws {
        resultValues.append(result)
        switch result {
        case .success:
            completedCount += 1
            successfulCount += 1
        case .archiveCompleted:
            break
        case .unsupported:
            completedCount += 1
            unsupportedCount += 1
        case .failure(let failure):
            completedCount += 1
            if failure.message == "Cancelled" {
                cancelledCount += 1
            } else {
                failedCount += 1
                failureValues.append(failure)
            }
        }
    }

    var summary: ScanSummary {
        ScanSummary(
            discovered: discoveredCount,
            completed: completedCount,
            successful: successfulCount,
            failed: failedCount,
            unsupported: unsupportedCount,
            cancelled: cancelledCount,
            failures: failureValues
        )
    }

    var results: [ScanPipelineResult] {
        resultValues
    }
}

enum ScanPlanner {
    static func makePlan(
        mode: ScanMode,
        items: [ScanInventoryItem],
        sourceURLs: [ScanItemIdentity: URL],
        currentFingerprints: [ScanItemIdentity: ScanFingerprint]
    ) -> ScanPlan {
        let candidates = items.compactMap { item -> ScanCandidate? in
            guard let sourceURL = sourceURLs[item.identity] else { return nil }
            let currentFingerprint = currentFingerprints[item.identity] ?? item.fingerprint
            guard ScanSelection.includes(item, mode: mode, currentFingerprint: currentFingerprint) else {
                return nil
            }
            return ScanCandidate(
                identity: item.identity,
                fingerprint: currentFingerprint,
                sourceURL: sourceURL,
                route: item.route
            )
        }

        return ScanPlan(
            mode: mode,
            candidates: candidates.sorted {
                if $0.identity.path != $1.identity.path {
                    return $0.identity.path.localizedStandardCompare($1.identity.path) == .orderedAscending
                }
                return ($0.identity.archiveEntry ?? "") < ($1.identity.archiveEntry ?? "")
            }
        )
    }
}

protocol ScanArchiveProvider: Sendable {
    func listMembers(
        in archiveURL: URL,
        supportedExtensions: Set<String>
    ) async throws -> ScanArchiveListing

    func materialize(
        archiveURL: URL,
        entryPath: String
    ) async throws -> URL

    func materializeEntries(
        archiveURL: URL,
        entryPaths: [String]
    ) async throws -> URL

    func materializeArchive(at archiveURL: URL) async throws -> URL

    func materializeEntriesForScan(
        archiveURL: URL,
        entryPaths: [String]
    ) async throws -> URL

    func materializeArchiveForScan(at archiveURL: URL) async throws -> URL

    func discardScanMaterialization(at rootURL: URL) async
}

extension ScanArchiveProvider {
    // Test and future providers can retain their existing behavior; the native
    // provider overrides these with short-lived scan scratch directories.
    func materializeEntriesForScan(archiveURL: URL, entryPaths: [String]) async throws -> URL {
        try await materializeEntries(archiveURL: archiveURL, entryPaths: entryPaths)
    }

    func materializeArchiveForScan(at archiveURL: URL) async throws -> URL {
        try await materializeArchive(at: archiveURL)
    }

    func discardScanMaterialization(at rootURL: URL) async {}
}

protocol ScanFormatHandler: Sendable {
    var descriptor: ScanPluginDescriptor { get }

    func inspect(fileURL: URL, route: ScanRoute) async throws -> ScanInspection
}

struct ScanPluginHandlerRegistry: Sendable {
    private let handlers: [String: any ScanFormatHandler]

    init(handlers: [any ScanFormatHandler]) {
        self.handlers = Dictionary(
            handlers.map { ($0.descriptor.pluginID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func handler(for route: ScanRoute) -> (any ScanFormatHandler)? {
        handlers[route.pluginID]
    }
}

protocol ScanResultSink: Sendable {
    func accept(_ result: ScanPipelineResult) async throws
}
