import Observation

@MainActor @Observable
final class PlaylistQueueCoordinator {
    private(set) var tracks: [TrackItem] = []
    var primarySelection: TrackItem.ID?
    var selection: Set<TrackItem.ID> = []
    private(set) var contentRevision = 0

    func replaceTracks(with tracks: [TrackItem]) {
        self.tracks = tracks
        contentRevision &+= 1
    }
}
