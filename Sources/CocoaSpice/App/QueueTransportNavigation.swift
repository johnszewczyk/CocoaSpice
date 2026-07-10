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
        selectedTrackID: String?,
        playlist: [TrackItem]
    ) -> TrackItem? {
        if let nextTrack = adjacentTrack(
            from: currentTrack,
            in: playlist,
            direction: .next,
            wraps: false
        ) {
            return nextTrack
        }

        if let selectedTrackID,
           let selectedTrack = playlist.first(where: { $0.id == selectedTrackID }) {
            return selectedTrack
        }

        return playlist.first
    }

    static func reachedCompletionThreshold(
        elapsedSeconds: TimeInterval,
        totalPlaybackSeconds: Int
    ) -> Bool {
        let completionThreshold = max(0, Double(totalPlaybackSeconds) - 0.35)
        return elapsedSeconds >= completionThreshold
    }
}
