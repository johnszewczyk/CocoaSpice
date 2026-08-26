import Foundation
import CatalogSessionCore
import PlaybackRequestCore

/// Owns the identity and cancellation lifecycle of the pending playback
/// request. Playback UI and decoder state remain with `PlayerViewModel`.
@MainActor
final class PlaybackRequestState {
    private let taskOwner = PlaybackRequestLifecycle()

    var pendingTrack: TrackItem?
    var reachedEnd = false
    var didAutoAdvance = false

    func begin(track: TrackItem) -> Int {
        let generation = taskOwner.begin()
        pendingTrack = track
        reachedEnd = false
        didAutoAdvance = false
        return generation
    }

    func install(_ task: Task<Void, Never>, generation: Int) {
        taskOwner.install(task, generation: generation)
    }

    func isCurrent(_ generation: Int) -> Bool {
        taskOwner.isCurrent(generation)
    }

    func finish(generation: Int) {
        taskOwner.finish(generation: generation)
    }

    func cancel(clearPendingTrack: Bool = true) {
        taskOwner.cancel()
        if clearPendingTrack {
            pendingTrack = nil
        }
    }
}
