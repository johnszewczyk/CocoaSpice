import Foundation
import MediaPlayer

struct RemoteTransportNowPlaying: Equatable, Sendable {
    let title: String
    let albumTitle: String
    let elapsedSeconds: TimeInterval
    let durationSeconds: TimeInterval
    let isPlaying: Bool
}

@MainActor
final class RemoteTransportController {
    private var isConfigured = false
    private var lastPublishedNowPlaying: RemoteTransportNowPlaying?

    func configure(
        previous: @escaping @MainActor () -> Void,
        play: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor () -> Void,
        togglePlayPause: @escaping @MainActor () -> Void,
        next: @escaping @MainActor () -> Void
    ) {
        guard !isConfigured else { return }
        isConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true

        commandCenter.previousTrackCommand.addTarget { _ in
            Task { @MainActor in previous() }
            return .success
        }

        commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in play() }
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in togglePlayPause() }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { _ in
            Task { @MainActor in next() }
            return .success
        }
    }

    func updateNowPlaying(_ nowPlaying: RemoteTransportNowPlaying) {
        guard nowPlaying != lastPublishedNowPlaying else { return }
        lastPublishedNowPlaying = nowPlaying

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = nowPlaying.title
        info[MPMediaItemPropertyAlbumTitle] = nowPlaying.albumTitle
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nowPlaying.elapsedSeconds
        info[MPMediaItemPropertyPlaybackDuration] = nowPlaying.durationSeconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = nowPlaying.isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = nowPlaying.isPlaying ? .playing : .paused
    }
}
