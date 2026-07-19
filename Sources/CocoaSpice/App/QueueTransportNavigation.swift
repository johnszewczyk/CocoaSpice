import Foundation

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
        if let currentTrack {
            return currentTrack
        }

        if let selectedTrackID,
           let selectedTrack = playlist.first(where: { $0.id == selectedTrackID }) {
            return selectedTrack
        }

        return playlist.first
    }

    static func adjacentTrack(
        from currentTrack: TrackItem?,
        in playlist: [TrackItem],
        direction: QueueTransportDirection,
        wraps: Bool
    ) -> TrackItem? {
        guard let currentTrack,
              let currentIndex = playlist.firstIndex(of: currentTrack),
              !playlist.isEmpty else {
            return nil
        }

        switch direction {
        case .next:
            let nextIndex = playlist.index(after: currentIndex)
            if nextIndex == playlist.endIndex {
                return wraps ? playlist.first : nil
            }
            return playlist[nextIndex]
        case .previous:
            if currentIndex == playlist.startIndex {
                return wraps ? playlist.last : nil
            }
            return playlist[playlist.index(before: currentIndex)]
        }
    }

    static func completionAdvanceTarget(
        currentTrack: TrackItem?,
        playlist: [TrackItem]
    ) -> TrackItem? {
        guard !playlist.isEmpty else { return nil }
        guard let currentTrack,
              playlist.contains(currentTrack) else {
            // A replacement queue can intentionally keep the old track playing
            // until it finishes. That old identity is not an anchor in the new
            // queue, so continuation begins at the replacement queue's head.
            return playlist.first
        }

        return adjacentTrack(
            from: currentTrack,
            in: playlist,
            direction: .next,
            wraps: false
        )
    }
}
