import Foundation
import MediaPlayer

@MainActor
final class RemoteTransportController {
    private var isConfigured = false

    func configure(with model: PlayerViewModel) {
        guard !isConfigured else { return }
        isConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true

        commandCenter.previousTrackCommand.addTarget { [weak model] _ in
            guard let model else { return .commandFailed }
            model.handleMediaPreviousCommand()
            return .success
        }

        commandCenter.playCommand.addTarget { [weak model] _ in
            guard let model else { return .commandFailed }
            model.handleMediaPlayCommand()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak model] _ in
            guard let model else { return .commandFailed }
            model.handleMediaPauseCommand()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak model] _ in
            guard let model else { return .commandFailed }
            model.handleMediaPlayPauseCommand()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak model] _ in
            guard let model else { return .commandFailed }
            model.handleMediaNextCommand()
            return .success
        }
    }

    func updateNowPlaying(from model: PlayerViewModel) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = model.currentSongTitle
        info[MPMediaItemPropertyAlbumTitle] = model.currentGameTitle
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = model.playbackElapsedSeconds
        info[MPMediaItemPropertyPlaybackDuration] = Double(model.totalPlaybackSeconds)
        info[MPNowPlayingInfoPropertyPlaybackRate] = model.isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = model.isPlaying ? .playing : .paused
    }
}
