import Foundation
import VGMBoyKit

/// CocoaSpice's playlist-facing wrapper around the bundled VGMBoyKit core.
/// Queue ownership remains here; decoded audio, timing, EQ, and transport do not.
final class PlaybackEngine: @unchecked Sendable {
    private let controller = PlaybackController()
    private let queue = DispatchQueue(label: "CocoaSpice.vgmboy-playback", qos: .userInitiated)
    private let exportQueue = DispatchQueue(label: "CocoaSpice.vgmboy-export", qos: .utility)
    private let requestLock = NSLock()
    private var latestPlaybackRequest = 0
    private var playbackStateHandler: (@Sendable (PlaybackStatusSnapshot) -> Void)?
    private var currentMaterializedPath: String?
    private(set) var currentTrack: TrackItem?
    private(set) var currentPlaybackPlan = PlaybackPlan(preFadeSeconds: 150, fadeSeconds: 6, usesNativeEnding: false, isLongPlay: false)
    private let controlSurface: PlaybackControlSurface

    init() {
        controlSurface = controller.controlSurface
        _ = controller.subscribe { [weak self] event in
            guard let self, let status = event.status else { return }
            self.publish(status: status)
        }
    }

    func setAppVolume(_ volume: Float) {
        performOutputControl(.setOutputVolume, payload: .init(outputVolume: AudioOutputVolume.clamped(volume)))
    }

    func setMonoEnabled(_ enabled: Bool) {
        performOutputControl(.setMonoEnabled, payload: .init(monoEnabled: enabled))
    }

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

    func play(track: TrackItem, plan: PlaybackPlan, tempo: PlaybackTempo, requestID: Int) async throws {
        try await run {
            guard self.isLatest(requestID) else { throw CancellationError() }
            try self.load(track: track, plan: plan, tempo: tempo, resumeAt: 0, autoplay: true)
        }
    }

    func reconfigureCurrentTrack(plan: PlaybackPlan, tempo: PlaybackTempo) async throws {
        try await run {
            guard let track = self.currentTrack else { throw PlaybackSessionError.notLoaded }
            let status = self.controller.perform(.init(command: .status)).status
            try self.load(track: track, plan: plan, tempo: tempo, resumeAt: status?.elapsedSeconds ?? 0, autoplay: status?.isPlaying ?? false)
        }
    }

    func setTempo(_ tempo: PlaybackTempo) async throws {
        try await run {
            guard let track = self.currentTrack,
                  FormatRegistry.family(for: track.playablePathExtension)?.supportsTempo == true else {
                return
            }
            try self.requireSuccess(self.controller.perform(.init(
                command: .setTempo,
                payload: .init(tempo: tempo.multiplier)
            )))
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
    func beginFadedSkip(duration: TimeInterval) async -> Int? {
        await run {
            guard self.currentTrack != nil else { return nil }
            let status = self.controller.perform(.init(command: .status)).status
            guard status?.isPlaying == true else { return nil }
            let milliseconds = max(1, Int((duration * 1_000).rounded(.up)))
            let event = self.controller.perform(.init(
                command: .rampOutputGain,
                payload: .init(outputGain: 0, rampMilliseconds: milliseconds)
            ))
            guard event.kind != .error else { return nil }
            return status?.diagnostics.generation
        }
    }

    func isCurrentGeneration(_ generation: Int) async -> Bool {
        await run {
            guard self.currentTrack != nil else { return false }
            return self.controller.perform(.init(command: .status)).status?.diagnostics.generation == generation
        }
    }

    func statusSnapshot() async -> PlaybackStatusSnapshot {
        await run { self.snapshot(self.controller.perform(.init(command: .status)).status) }
    }

    func diagnosticsSnapshot() -> PlaybackDiagnosticsSnapshot {
        let diagnostics = controller.diagnostics()
        let status = controller.perform(.init(command: .status)).status
        let statistics = status?.statistics
        return PlaybackDiagnosticsSnapshot(
            decoderFamily: statistics?.decoderFamily,
            decoderSampleRate: statistics?.decoderSampleRate ?? 0,
            decodedFrames: statistics?.decodedFrames ?? 0,
            audiblePositionFrames: statistics?.audiblePositionFrames ?? 0,
            tempo: statistics?.tempo ?? 1,
            bufferedFrames: Int64(diagnostics.bufferedFrames),
            ringBufferFrames: Int64(diagnostics.capacityFrames),
            underrunCount: diagnostics.underrunCount,
            clippedSampleCount: 0,
            sampleRate: diagnostics.sampleRate,
            outputHealth: diagnostics.isOutputRunning ? .running : .inactive
        )
    }
    func currentTrackID() async -> TrackItem.ID? { await run { self.currentTrack?.id } }

    func seek(to seconds: TimeInterval) async throws {
        try await run {
            try self.requireSuccess(self.controller.perform(.init(command: .seek, payload: .init(positionMilliseconds: Int(max(0, seconds) * 1_000)))))
        }
    }

    /// Archive materialization remains a CocoaSpice concern. Once a naked
    /// playable path is ready, VGMBoy owns the offline decode and AAC write.
    func exportAAC(track: TrackItem, plan: PlaybackPlan, outputDirectory: URL, filenameStem: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            exportQueue.async {
                do {
                    let sourceURL = try ZipArchiveSupport.materializePlayableFile(for: track)
                    let result = try self.controller.exportAAC(AACExportRequest(
                        sourcePath: sourceURL.path,
                        trackIndex: track.trackIndex,
                        outputDirectory: outputDirectory,
                        filenameStem: filenameStem,
                        playMilliseconds: plan.preFadeSeconds * 1_000,
                        fadeMilliseconds: plan.fadeSeconds * 1_000
                    ))
                    continuation.resume(returning: result.outputURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func load(track: TrackItem, plan: PlaybackPlan, tempo: PlaybackTempo, resumeAt: TimeInterval, autoplay: Bool) throws {
        let url = try ZipArchiveSupport.materializePlayableFile(for: track)
        let timing = try PlaybackTimingRequest.standard(
            path: url.path,
            longPlayEnabled: plan.isLongPlay,
            manualPlayMilliseconds: plan.preFadeSeconds * 1_000,
            fadeMilliseconds: plan.fadeSeconds * 1_000,
            unknownDurationMilliseconds: plan.unknownDurationSeconds * 1_000
        )
        // A mode command normally reconfigures the currently loaded track.
        // Supplying it atomically with the new load avoids briefly resuming
        // that old decoder, then tearing it back down before the selected
        // track starts. The output sees one prime and one de-click ramp.
        try requireSuccess(controller.perform(.init(command: .load, payload: .init(
            path: url.path,
            trackIndex: track.trackIndex,
            tempo: tempo.multiplier,
            playbackMode: timing.playbackMode,
            playMilliseconds: timing.playMilliseconds,
            fadeMilliseconds: timing.fadeMilliseconds,
            unknownDurationMilliseconds: timing.unknownDurationMilliseconds
        ))))
        if resumeAt > 0 {
            try requireSuccess(controller.perform(.init(command: .seek, payload: .init(positionMilliseconds: Int(resumeAt * 1_000)))))
        }
        if autoplay { try requireSuccess(controller.perform(.init(command: .play))) }
        currentTrack = track
        currentMaterializedPath = url.path
        currentPlaybackPlan = plan
    }

    private func requireSuccess(_ event: PlaybackControlEvent) throws {
        if event.kind == .error { throw NSError(domain: "VGMBoyKit", code: 1, userInfo: [NSLocalizedDescriptionKey: event.message ?? "VGMBoy playback command failed."]) }
    }

    /// One mapping point for the CocoaSpice Audio panel. When VGMBoy grows a
    /// new output feature, its capability and typed request are added here;
    /// the playlist/frontend never reaches into decoder or audio-engine code.
    private func performOutputControl(_ command: PlaybackControlCommand, payload: PlaybackControlPayload) {
        guard controlSurface.supports(command) else {
            assertionFailure("Bundled VGMBoyKit does not expose \(command.rawValue).")
            return
        }
        let event = controller.perform(.init(command: command, payload: payload))
        if event.kind == .error {
            assertionFailure(event.message ?? "VGMBoyKit rejected \(command.rawValue).")
        }
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
