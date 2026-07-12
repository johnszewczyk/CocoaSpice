import Foundation
import Dispatch

enum PlaybackInspection {
    static func inspectMetadata(track: TrackItem) async throws -> TrackMetadata {
        try Task.checkCancellation()
        return try await PlaybackInspectionGate.withLock {
            try Task.checkCancellation()
            let decoder = try PlaybackDecoderFactory.makeDecoder(track: track, sampleRate: Int(44_100))
            return try decoder.metadata()
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
