import Foundation
import CatalogSessionCore
import PlaybackRequestCore

/// Owns the identity and cancellation lifecycle of the pending playback
/// request. Playback UI and decoder state remain with `PlayerViewModel`.
@MainActor
final class PlaybackRequestState {
    private let lifecycle = PlaybackRequestLifecycle()

    var pendingTrack: TrackItem?
    var reachedEnd = false

    func begin(track: TrackItem) -> Int {
        let generation = lifecycle.begin()
        pendingTrack = track
        reachedEnd = false
        return generation
    }

    func install(_ task: Task<Void, Never>, generation: Int) {
        lifecycle.install(task, generation: generation)
    }

    func isCurrent(_ generation: Int) -> Bool {
        lifecycle.isCurrent(generation)
    }

    func finish(generation: Int) {
        lifecycle.finish(generation: generation)
    }

    func cancel(clearPendingTrack: Bool = true) {
        lifecycle.cancel()
        if clearPendingTrack {
            pendingTrack = nil
        }
    }
}
