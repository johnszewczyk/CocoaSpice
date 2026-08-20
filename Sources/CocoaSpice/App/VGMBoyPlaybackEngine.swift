import Foundation
import VGMBoyKit

/// CocoaSpice's playlist-facing wrapper around the bundled VGMBoyKit core.
/// Queue ownership remains here; decoded audio, timing, EQ, and transport do not.
final class PlaybackEngine: @unchecked Sendable {
    private let controller = PlaybackController()
    private let queue = DispatchQueue(label: "CocoaSpice.vgmboy-playback", qos: .userInitiated)
    private let requestLock = NSLock()
    private var latestPlaybackRequest = 0
    private var playbackStateHandler: (@Sendable (PlaybackStatusSnapshot) -> Void)?
    private var currentMaterializedPath: String?
    private(set) var currentTrack: TrackItem?
    private(set) var currentPlaybackPlan = PlaybackPlan(preFadeSeconds: 150, fadeSeconds: 6, totalSeconds: 156, usesNativeEnding: false, isLongPlay: false)

    init() {
        _ = controller.subscribe { [weak self] event in
            guard let self, let status = event.status else { return }
            self.publish(status: status)
        }
    }

    func setSpectrumLevelHandler(_ handler: (@Sendable ([Float]) -> Void)?) { handler?([]) }
    func setSpectrumEnabled(_ enabled: Bool) {}
    func setSpectrumBandCount(_ bandCount: Int) {}
    func setAppVolume(_ volume: Float) {}
    func setMonoEnabled(_ enabled: Bool) {}

    func setEqualizer(enabled: Bool, bandGains: [Float]) {
        _ = controller.perform(.init(command: .setEqualizer, payload: .init(equalizer: .init(enabled: enabled, gainsDecibels: bandGains))))
    }

    func setPlaybackStateHandler(_ handler: (@Sendable (PlaybackStatusSnapshot) -> Void)?) {
        queue.async { self.playbackStateHandler = handler }
    }

    func reservePlaybackRequest() -> Int {
        requestLock.lock(); defer { requestLock.unlock() }
        latestPlaybackRequest += 1
        return latestPlaybackRequest
    }

    func play(track: TrackItem, plan: PlaybackPlan, requestID: Int) async throws -> TrackMetadata {
        try await run {
            guard self.isLatest(requestID) else { throw CancellationError() }
            return try self.load(track: track, plan: plan, resumeAt: 0, autoplay: true)
        }
    }

    func reconfigureCurrentTrack(plan: PlaybackPlan) async throws -> TrackMetadata {
        try await run {
            guard let track = self.currentTrack else { throw PlaybackSessionError.notLoaded }
            let status = self.controller.perform(.init(command: .status)).status
            return try self.load(track: track, plan: plan, resumeAt: status?.elapsedSeconds ?? 0, autoplay: status?.isPlaying ?? false)
        }
    }

    func setPlaying(_ shouldPlay: Bool) async -> Bool {
        await run {
            let event = self.controller.perform(.init(command: shouldPlay ? .play : .pause))
            return event.status?.isPlaying ?? false
        }
    }

    func stopPlayback() async {
        await run {
            _ = self.controller.perform(.init(command: .stop))
            self.currentTrack = nil
            self.currentMaterializedPath = nil
            ZipArchiveSupport.discardDisposablePlaybackMaterialization()
        }
    }

    func stop() async { await stopPlayback() }
    func beginFadedSkip(duration: TimeInterval) async -> Int? { nil }
    func isCurrentGeneration(_ generation: Int) async -> Bool { false }

    func statusSnapshot() async -> PlaybackStatusSnapshot {
        await run { self.snapshot(self.controller.perform(.init(command: .status)).status) }
    }

    func diagnosticsSnapshot() -> PlaybackDiagnosticsSnapshot { .idle }
    func currentTrackID() async -> TrackItem.ID? { await run { self.currentTrack?.id } }

    func seek(to seconds: TimeInterval) async throws {
        try await run {
            try self.requireSuccess(self.controller.perform(.init(command: .seek, payload: .init(positionMilliseconds: Int(max(0, seconds) * 1_000)))))
        }
    }

    private func load(track: TrackItem, plan: PlaybackPlan, resumeAt: TimeInterval, autoplay: Bool) throws -> TrackMetadata {
        let url = try ZipArchiveSupport.materializePlayableFile(for: track)
        let inspection = try AudioInspector.inspect(path: url.path)
        guard inspection.tracks.indices.contains(track.trackIndex) else {
            throw PlaybackControlError.invalidPayload("Track index is not available for this file.")
        }
        let mode: VGMBoyKit.PlaybackMode = plan.isLongPlay ? .longPlay : (plan.usesNativeEnding ? .fileDefault : .timed)
        try requireSuccess(controller.perform(.init(command: .setPlaybackMode, payload: .init(playbackMode: mode, playMilliseconds: plan.preFadeSeconds * 1_000, fadeMilliseconds: plan.fadeSeconds * 1_000))))
        try requireSuccess(controller.perform(.init(command: .load, payload: .init(path: url.path, trackIndex: track.trackIndex))))
        if resumeAt > 0 {
            try requireSuccess(controller.perform(.init(command: .seek, payload: .init(positionMilliseconds: Int(resumeAt * 1_000)))))
        }
        if autoplay { try requireSuccess(controller.perform(.init(command: .play))) }
        currentTrack = track
        currentMaterializedPath = url.path
        currentPlaybackPlan = plan
        return cocoaMetadata(inspection.tracks[track.trackIndex])
    }

    private func cocoaMetadata(_ metadata: VGMBoyKit.TrackMetadata) -> TrackMetadata {
        TrackMetadata(game: metadata.game, song: metadata.song, system: metadata.system, author: metadata.author, comment: "", introLengthMs: metadata.introMs, loopLengthMs: metadata.loopMs, playLengthMs: metadata.playMs, fadeLengthMs: metadata.fadeMs)
    }

    private func requireSuccess(_ event: PlaybackControlEvent) throws {
        if event.kind == .error { throw NSError(domain: "VGMBoyKit", code: 1, userInfo: [NSLocalizedDescriptionKey: event.message ?? "VGMBoy playback command failed."]) }
    }

    private func snapshot(_ status: VGMBoyKit.PlaybackStatus?) -> PlaybackStatusSnapshot {
        PlaybackStatusSnapshot(currentTrackID: currentTrack?.id, isPlaying: status?.isPlaying ?? false, elapsedSeconds: status?.elapsedSeconds ?? 0, reachedEnd: status?.reachedEnd ?? false)
    }

    private func publish(status: VGMBoyKit.PlaybackStatus) {
        queue.async { self.playbackStateHandler?(self.snapshot(status)) }
    }

    private func isLatest(_ requestID: Int) -> Bool {
        requestLock.lock(); defer { requestLock.unlock() }
        return requestID == latestPlaybackRequest
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in queue.async { continuation.resume(returning: work()) } }
    }
}

struct PlaybackPlan: Equatable, Sendable {
    let preFadeSeconds: Int
    let fadeSeconds: Int
    let totalSeconds: Int
    let usesNativeEnding: Bool
    let isLongPlay: Bool
}

struct PlaybackStatusSnapshot: Sendable {
    let currentTrackID: TrackItem.ID?
    let isPlaying: Bool
    let elapsedSeconds: TimeInterval
    let reachedEnd: Bool
}

/// Presentation constants for the unchanged CocoaSpice controls. Equalizer
/// processing itself is owned by VGMBoyKit.
enum AudioEqualizer {
    static let bandFrequencies = EqualizerConfiguration.bandFrequencies
    static let gainRange = EqualizerConfiguration.gainRange
    static func clampedGain(_ value: Float) -> Float { min(max(value, gainRange.lowerBound), gainRange.upperBound) }
}

enum AudioOutputVolume {
    static let range: ClosedRange<Float> = 0...1
    static func clamped(_ value: Float) -> Float { min(max(value, range.lowerBound), range.upperBound) }
}
