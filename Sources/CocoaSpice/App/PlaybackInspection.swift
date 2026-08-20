import Foundation
import VGMBoyKit

enum PlaybackInspection {
    static let metadataWorkerLimit = 2

    static func inspectMetadata(track: TrackItem) async throws -> TrackMetadata {
        try inspectMetadata(track: track, fileURL: ZipArchiveSupport.materializePlayableFile(for: track))
    }

    static func inspectMetadata(track: TrackItem, fileURL: URL) throws -> TrackMetadata {
        let inspection = try AudioInspector.inspect(path: fileURL.path)
        guard inspection.tracks.indices.contains(track.trackIndex) else {
            throw PlaybackControlError.invalidPayload("Track index is not available for this file.")
        }
        return metadata(inspection.tracks[track.trackIndex])
    }

    static func inspectPlayableTracks(fileURL: URL) async throws -> [InspectedTrack] {
        let inspection = try AudioInspector.inspect(path: fileURL.path)
        return inspection.tracks.map { value in
            InspectedTrack(track: TrackItem(url: fileURL, trackIndex: value.index, trackCount: inspection.trackCount), metadata: metadata(value))
        }
    }

    static func prepareMetadataInspectionJobs(tracks: [TrackItem]) -> [PlaylistMetadataInspectionJob] {
        tracks.compactMap { track in
            guard let url = try? ZipArchiveSupport.materializePlayableFile(for: track) else { return nil }
            return PlaylistMetadataInspectionJob(track: track, fileURL: url)
        }
    }

    private static func metadata(_ value: VGMBoyKit.TrackMetadata) -> TrackMetadata {
        TrackMetadata(game: value.game, song: value.song, system: value.system, author: value.author, comment: "", introLengthMs: value.introMs, loopLengthMs: value.loopMs, playLengthMs: value.playMs, fadeLengthMs: value.fadeMs)
    }
}

struct PlaylistMetadataInspectionJob: Sendable {
    let track: TrackItem
    let fileURL: URL
}
