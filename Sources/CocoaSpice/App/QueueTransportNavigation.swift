import Foundation
import PlaybackQueueCore

enum QueueTransportDirection {
    case previous
    case next
}

enum QueueTransportNavigation {
    static func transportPlaybackTarget(
        currentTrack: TrackItem?,
        selectedTrackID: String?,
        playlist: [TrackItem]
    ) -> TrackItem? {
        guard let targetID = PlaybackQueueNavigation.transportPlaybackTarget(
            currentTrackID: currentTrack?.id,
            selectedTrackID: selectedTrackID,
            playlistIDs: playlist.map(\.id)
        ) else {
            return nil
        }
        return playlist.first { $0.id == targetID }
    }

    static func adjacentTrack(
        from currentTrack: TrackItem?,
        in playlist: [TrackItem],
        direction: QueueTransportDirection,
        wraps: Bool
    ) -> TrackItem? {
        let sharedDirection: PlaybackQueueDirection = switch direction {
        case .previous: .previous
        case .next: .next
        }
        guard let targetID = PlaybackQueueNavigation.adjacentTrackID(
            currentTrackID: currentTrack?.id,
            playlistIDs: playlist.map(\.id),
            direction: sharedDirection,
            wraps: wraps
        ) else {
            return nil
        }
        return playlist.first { $0.id == targetID }
    }

}
