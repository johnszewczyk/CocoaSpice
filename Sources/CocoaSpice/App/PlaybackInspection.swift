import Foundation
import Dispatch

struct PlaylistMetadataArchiveBatch: Equatable, Sendable {
    let archiveURL: URL
    let entryPaths: [String]
}

struct PlaylistMetadataInspectionJob: Sendable {
    let track: TrackItem
    let fileURL: URL
}

enum PlaybackInspection {
    static let metadataWorkerLimit = 2

    static func inspectMetadata(track: TrackItem) async throws -> TrackMetadata {
        try Task.checkCancellation()
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        return try await inspectMetadata(track: track, fileURL: fileURL)
    }

    static func inspectMetadata(
        track: TrackItem,
        fileURL: URL
    ) async throws -> TrackMetadata {
        try Task.checkCancellation()
        return try await PlaybackInspectionGate.withLock {
            try Task.checkCancellation()
            let inspector = try PlaybackDecoderFactory.makeInspector(fileURL: fileURL)
            return try inspector.metadata(trackIndex: track.trackIndex)
        }
    }

    static func archiveBatches(for tracks: [TrackItem]) -> [PlaylistMetadataArchiveBatch] {
        var archiveOrder: [URL] = []
        var entryPathsByArchive: [URL: [String]] = [:]
        var seenEntriesByArchive: [URL: Set<String>] = [:]

        for track in tracks {
            guard case .zipEntry(let archiveURL, let entryPath) = track.source else { continue }
            if entryPathsByArchive[archiveURL] == nil {
                archiveOrder.append(archiveURL)
                entryPathsByArchive[archiveURL] = []
                seenEntriesByArchive[archiveURL] = []
            }
            if seenEntriesByArchive[archiveURL, default: []].insert(entryPath).inserted {
                entryPathsByArchive[archiveURL, default: []].append(entryPath)
            }
        }

        return archiveOrder.map {
            PlaylistMetadataArchiveBatch(
                archiveURL: $0,
                entryPaths: entryPathsByArchive[$0] ?? []
            )
        }
    }

    static func prepareMetadataInspectionJobs(
        tracks: [TrackItem]
    ) -> [PlaylistMetadataInspectionJob] {
        var preparedURLByContainerID: [String: URL] = [:]
        for track in tracks {
            if case .file(let fileURL) = track.source {
                preparedURLByContainerID[track.containerID] = fileURL
            }
        }

        for batch in archiveBatches(for: tracks) {
            if Task.isCancelled { return [] }
            guard let root = try? ZipArchiveSupport.materializeInspectionSet(
                archiveURL: batch.archiveURL,
                entryPaths: batch.entryPaths
            ) else {
                continue
            }
            for entryPath in batch.entryPaths {
                let track = TrackItem(archiveURL: batch.archiveURL, entryPath: entryPath)
                preparedURLByContainerID[track.containerID] = ZipArchiveSupport.archiveMemberURL(
                    in: root,
                    entryPath: entryPath
                )
            }
        }

        return tracks.compactMap { track in
            preparedURLByContainerID[track.containerID].map {
                PlaylistMetadataInspectionJob(track: track, fileURL: $0)
            }
        }
    }

    static func inspectPlayableTracks(fileURL: URL) async throws -> [InspectedTrack] {
        try Task.checkCancellation()
        return try await PlaybackInspectionGate.withLock {
            try Task.checkCancellation()
            let inspector = try PlaybackDecoderFactory.makeInspector(fileURL: fileURL)
            let trackCount = max(1, inspector.trackCount)
            return try (0..<trackCount).map { trackIndex in
                try Task.checkCancellation()
                let track = TrackItem(url: fileURL, trackIndex: trackIndex, trackCount: trackCount)
                let metadata = try inspector.metadata(trackIndex: trackIndex)
                return InspectedTrack(track: track, metadata: metadata)
            }
        }
    }
}

private enum PlaybackInspectionGate {
    private static let queue = DispatchQueue(
        label: "com.cocoaspice.playback-inspection",
        qos: .utility
    )

    static func withLock<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
