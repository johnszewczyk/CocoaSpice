@preconcurrency import AVFoundation
import Foundation
import CGME

final class SPCPlaybackEngine: @unchecked Sendable {
    private let sampleRate: Double = 44_100
    private let channels: AVAudioChannelCount = 2
    private let chunkFrameCount = 4_096
    private let maxQueuedBuffers = 3
    private let queue = DispatchQueue(label: "SPCBoy.playback", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let requestLock = NSLock()
    private let spectrumAnalyzer: SpectrumBandAnalyzer
    private var currentPlaybackDuration: TimeInterval = 0
    private var currentStream: SPCStreamSession?
    private var playbackStartedAt: Date?
    private var pauseStartedAt: Date?
    private var accumulatedPauseTime: TimeInterval = 0
    private var streamGeneration = 0
    private var queuedBufferCount = 0
    private var spectrumLevelHandler: (@Sendable ([Float]) -> Void)?
    private var playbackStateHandler: (@Sendable (PlaybackStatusSnapshot) -> Void)?
    private var configurationChangeObserver: NSObjectProtocol?
    private var latestPlaybackRequest = 0

    private(set) var currentTrack: TrackItem?
    private(set) var isPlaying = false
    private(set) var currentPlaybackPlan = PlaybackPlan(preFadeSeconds: 150, fadeSeconds: 6, totalSeconds: 156, usesNativeEnding: false)

    init() {
        spectrumAnalyzer = SpectrumBandAnalyzer(sampleRate: Float(sampleRate))
        queue.sync {
            engine.attach(player)

            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            let mixerOutputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: mixerOutputFormat) { [weak self] buffer, _ in
                self?.handleSpectrumBuffer(buffer)
            }
            try? engine.start()
        }

        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.recoverFromConfigurationChange()
        }
    }

    deinit {
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
        }
    }

    func setSpectrumLevelHandler(_ handler: (@Sendable ([Float]) -> Void)?) {
        queue.async {
            self.spectrumLevelHandler = handler
        }
    }

    func setPlaybackStateHandler(_ handler: (@Sendable (PlaybackStatusSnapshot) -> Void)?) {
        queue.async {
            self.playbackStateHandler = handler
        }
    }

    func reservePlaybackRequest() -> Int {
        requestLock.lock()
        defer { requestLock.unlock() }
        latestPlaybackRequest += 1
        return latestPlaybackRequest
    }

    func play(
        track: TrackItem,
        plan: PlaybackPlan,
        requestID: Int
    ) async throws -> TrackMetadata {
        try await enqueue {
            guard self.isLatestPlaybackRequest(requestID) else {
                throw CancellationError()
            }
            return try self.loadRenderedTrack(
                track: track,
                plan: plan,
                resumeAt: 0,
                autoplay: true
            )
        }
    }

    private func isLatestPlaybackRequest(_ requestID: Int) -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return requestID == latestPlaybackRequest
    }

    func inspect(track: TrackItem) async throws -> TrackMetadata {
        try await Self.inspectMetadata(track: track)
    }

    nonisolated static func inspectMetadata(track: TrackItem) async throws -> TrackMetadata {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let decoder = try PlaybackDecoderFactory.makeDecoder(track: track, sampleRate: Int(44_100))
            return try decoder.metadata()
        }.value
    }

    nonisolated static func inspectPlayableTracks(fileURL: URL) async throws -> [InspectedTrack] {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let inspector = try PlaybackDecoderFactory.makeInspector(fileURL: fileURL)
            let trackCount = max(1, inspector.trackCount)
            return try (0..<trackCount).map { trackIndex in
                let track = TrackItem(url: fileURL, trackIndex: trackIndex, trackCount: trackCount)
                let metadata = try inspector.metadata(trackIndex: trackIndex)
                return InspectedTrack(track: track, metadata: metadata)
            }
        }.value
    }

    func togglePause() async -> Bool {
        await enqueue {
            if self.player.isPlaying {
                self.player.pause()
                self.pauseStartedAt = Date()
                self.isPlaying = false
            } else {
                if let pauseStartedAt = self.pauseStartedAt {
                    self.accumulatedPauseTime += Date().timeIntervalSince(pauseStartedAt)
                }
                self.pauseStartedAt = nil
                self.player.play()
                self.isPlaying = true
            }
            self.publishPlaybackState()
            return self.isPlaying
        }
    }

    func stopPlayback() async {
        await enqueue {
            self.resetPlaybackState()
        }
    }

    func stop() async {
        await stopPlayback()
    }

    private func recoverFromConfigurationChange() {
        queue.async {
            guard let currentStream = self.currentStream else { return }

            let wasPlaying = self.isPlaying
            let elapsedSeconds = self.elapsedPlaybackSeconds()

            do {
                self.engine.stop()
                self.player.stop()
                self.player.reset()
                try self.engine.start()
                try currentStream.seek(to: elapsedSeconds)
                try self.scheduleStreaming(autoplay: wasPlaying)
                self.isPlaying = wasPlaying
                self.publishPlaybackState()
            } catch {
                self.resetPlaybackState()
            }
        }
    }

    func statusSnapshot() async -> PlaybackStatusSnapshot {
        await enqueue {
            self.currentSnapshot()
        }
    }

    func currentTrackID() async -> TrackItem.ID? {
        await enqueue {
            self.currentTrack?.id
        }
    }

    func seek(to seconds: TimeInterval) async throws {
        try await enqueue {
            guard let currentStream = self.currentStream else { return }
            let clampedSeconds: TimeInterval
            if self.currentPlaybackPlan.usesNativeEnding {
                clampedSeconds = max(0, seconds)
            } else {
                clampedSeconds = max(0, min(seconds, self.currentPlaybackDuration))
            }
            let wasPlaying = self.isPlaying
            self.pauseStartedAt = nil
            self.accumulatedPauseTime = 0
            self.playbackStartedAt = Date().addingTimeInterval(-clampedSeconds)
            try currentStream.seek(to: clampedSeconds)
            try self.scheduleStreaming(autoplay: wasPlaying)
            self.isPlaying = wasPlaying
            self.publishPlaybackState()
        }
    }

    private func loadRenderedTrack(
        track: TrackItem,
        plan: PlaybackPlan,
        resumeAt requestedSeconds: TimeInterval,
        autoplay: Bool
    ) throws -> TrackMetadata {
        let stream = try SPCStreamSession(
            track: track,
            sampleRate: Int(sampleRate),
            totalSeconds: plan.usesNativeEnding ? 0 : plan.totalSeconds,
            loopSeconds: plan.preFadeSeconds,
            fadeSeconds: plan.fadeSeconds,
            chunkFrameCount: chunkFrameCount
        )

        player.stop()
        player.reset()

        currentStream = stream
        currentTrack = track
        currentPlaybackPlan = plan
        currentPlaybackDuration = TimeInterval(plan.totalSeconds)

        let clampedResume: TimeInterval
        if plan.usesNativeEnding {
            clampedResume = max(0, requestedSeconds)
        } else {
            clampedResume = max(0, min(requestedSeconds, currentPlaybackDuration))
        }
        playbackStartedAt = Date().addingTimeInterval(-clampedResume)
        accumulatedPauseTime = 0
        pauseStartedAt = autoplay ? nil : Date()

        try stream.seek(to: clampedResume)
        try scheduleStreaming(autoplay: autoplay)
        isPlaying = autoplay
        publishPlaybackState()
        return stream.metadata
    }

    private func scheduleStreaming(autoplay: Bool) throws {
        streamGeneration += 1
        queuedBufferCount = 0
        player.stop()
        player.reset()
        if !engine.isRunning {
            try engine.start()
        }

        try enqueueBuffersIfNeeded(generation: streamGeneration)

        if autoplay {
            player.play()
        }
    }

    private func enqueueBuffersIfNeeded(generation: Int) throws {
        guard generation == streamGeneration, let currentStream else { return }

        while queuedBufferCount < maxQueuedBuffers {
            guard let buffer = try currentStream.makeNextBuffer(
                sampleRate: sampleRate,
                channels: channels
            ) else {
                if queuedBufferCount == 0 {
                    finishPlayback(generation: generation)
                }
                break
            }

            queuedBufferCount += 1
            player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.handleConsumedBuffer(generation: generation)
                }
            }
        }
    }

    private func handleConsumedBuffer(generation: Int) {
        guard generation == streamGeneration else { return }
        queuedBufferCount = max(0, queuedBufferCount - 1)

        do {
            try enqueueBuffersIfNeeded(generation: generation)
        } catch {
            resetPlaybackState()
        }
    }

    private func finishPlayback(generation: Int) {
        guard generation == streamGeneration else { return }
        isPlaying = false
        pauseStartedAt = nil
        queuedBufferCount = 0
        spectrumAnalyzer.reset()
        spectrumLevelHandler?(Array(repeating: 0, count: SpectrumBandAnalyzer.bandCount))
        publishPlaybackState()
    }

    private func resetPlaybackState() {
        streamGeneration += 1
        player.stop()
        player.reset()
        isPlaying = false
        currentStream = nil
        currentTrack = nil
        currentPlaybackDuration = 0
        playbackStartedAt = nil
        pauseStartedAt = nil
        accumulatedPauseTime = 0
        queuedBufferCount = 0
        spectrumAnalyzer.reset()
        spectrumLevelHandler?(Array(repeating: 0, count: SpectrumBandAnalyzer.bandCount))
        publishPlaybackState()
    }

    private func publishPlaybackState() {
        playbackStateHandler?(currentSnapshot())
    }

    private func currentSnapshot() -> PlaybackStatusSnapshot {
        PlaybackStatusSnapshot(
            currentTrackID: currentTrack?.id,
            isPlaying: isPlaying,
            elapsedSeconds: elapsedPlaybackSeconds()
        )
    }

    private func elapsedPlaybackSeconds() -> TimeInterval {
        guard let playbackStartedAt else { return 0 }

        let effectiveNow = pauseStartedAt ?? Date()
        let elapsed = effectiveNow.timeIntervalSince(playbackStartedAt) - accumulatedPauseTime
        if currentPlaybackPlan.usesNativeEnding {
            return max(0, elapsed)
        }
        return max(0, min(elapsed, currentPlaybackDuration))
    }

    private func handleSpectrumBuffer(_ buffer: AVAudioPCMBuffer) {
        guard player.isPlaying else { return }
        guard let levels = spectrumAnalyzer.process(buffer: buffer) else { return }
        spectrumLevelHandler?(levels)
    }

    private func enqueue<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func enqueue<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: operation())
            }
        }
    }
}

private final class SpectrumBandAnalyzer: @unchecked Sendable {
    static let bandCount = 20

    private let sampleRate: Float
    // Log-spaced centers over a chiptune-oriented range.
    // This preserves an orderly analyzer layout while biasing the visible activity
    // toward the region that tends to matter most for retro game music.
    private let bandFrequencies: [Float] = [
        31.25, 39.76, 50.59, 64.37, 81.91,
        104.24, 132.66, 168.82, 214.83, 273.38,
        347.88, 442.67, 563.29, 716.80, 912.11,
        1160.63, 1476.88, 1879.32, 2391.45, 3043.15
    ]
    private let analysisFrameCount = 1_024
    private let minimumUpdateInterval: TimeInterval = 1.0 / 120.0
    private var analysisBuffer = Array(repeating: Float.zero, count: 1_024)
    private var lastPublishUptime: TimeInterval = 0

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }

    func reset() {
        lastPublishUptime = 0
    }

    func process(buffer: AVAudioPCMBuffer) -> [Float]? {
        let now = ProcessInfo.processInfo.systemUptime
        if lastPublishUptime > 0, (now - lastPublishUptime) < minimumUpdateInterval {
            return nil
        }
        lastPublishUptime = now

        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = min(Int(buffer.frameLength), analysisFrameCount)
        guard channelCount > 0, frameCount > 0 else { return nil }

        let inverseChannelCount = 1.0 / Float(channelCount)
        var rmsAccumulator: Float = 0
        for frame in 0..<frameCount {
            var monoSample: Float = 0
            for channel in 0..<channelCount {
                monoSample += channelData[channel][frame]
            }
            monoSample *= inverseChannelCount
            analysisBuffer[frame] = monoSample
            rmsAccumulator += monoSample * monoSample
        }

        if frameCount < analysisFrameCount {
            for frame in frameCount..<analysisFrameCount {
                analysisBuffer[frame] = 0
            }
        }

        let rms = sqrt(rmsAccumulator / Float(max(1, frameCount)))
        let floor = max(0.0001, rms)

        var levels = Array(repeating: Float.zero, count: Self.bandCount)
        for (index, centerFrequency) in bandFrequencies.enumerated() {
            let frequency = min(centerFrequency, sampleRate * 0.45)
            let magnitude = goertzelMagnitude(targetFrequency: frequency, sampleCount: analysisFrameCount)
            let relative = magnitude / floor
            levels[index] = min(1, log10f(1 + (relative * 6)) / log10f(7))
        }

        return levels
    }

    private func goertzelMagnitude(targetFrequency: Float, sampleCount: Int) -> Float {
        let omega = (2 * Float.pi * targetFrequency) / sampleRate
        let cosine = cos(omega)
        let sine = sin(omega)
        let coefficient = 2 * cosine

        var q0: Float = 0
        var q1: Float = 0
        var q2: Float = 0
        for index in 0..<sampleCount {
            q0 = coefficient * q1 - q2 + analysisBuffer[index]
            q2 = q1
            q1 = q0
        }

        let real = q1 - (q2 * cosine)
        let imaginary = q2 * sine
        let magnitudeSquared = max(0, (real * real) + (imaginary * imaginary))
        return sqrt(magnitudeSquared) / Float(sampleCount)
    }
}

private final class SPCStreamSession {
    let metadata: TrackMetadata
    let totalFrames: Int?

    private let decoder: any AudioTrackDecoder
    private let chunkFrameCount: Int
    private let fadeFrameCount: Int

    init(
        track: TrackItem,
        sampleRate: Int,
        totalSeconds: Int,
        loopSeconds: Int,
        fadeSeconds: Int,
        chunkFrameCount: Int
    ) throws {
        decoder = try PlaybackDecoderFactory.makeDecoder(track: track, sampleRate: sampleRate)
        metadata = try decoder.metadata()
        totalFrames = totalSeconds > 0 ? max(totalSeconds * sampleRate, 1) : nil
        self.chunkFrameCount = chunkFrameCount
        fadeFrameCount = max(0, fadeSeconds * sampleRate)
        decoder.configurePlayback(
            loopSeconds: loopSeconds,
            fadeSeconds: fadeSeconds,
            usesNativeEnding: totalSeconds <= 0
        )
    }

    func seek(to seconds: TimeInterval) throws {
        let clampedMilliseconds = max(0, min(Int(seconds * 1_000), totalMilliseconds))
        try decoder.seek(toMilliseconds: clampedMilliseconds)
    }

    func makeNextBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount
    ) throws -> AVAudioPCMBuffer? {
        if totalFrames == nil, decoder.trackEnded {
            return nil
        }

        let playedFrames = decoder.playedFrames
        if let totalFrames {
            guard playedFrames < totalFrames else { return nil }
        }

        let frameCount: Int
        if let totalFrames {
            frameCount = min(chunkFrameCount, totalFrames - playedFrames)
        } else {
            frameCount = chunkFrameCount
        }
        let chunkStartFrame = playedFrames
        let chunk = try decoder.decode(frameCount: frameCount)
        guard chunk.frameCount > 0 else { return nil }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(chunk.frameCount)
        ) else {
            throw SPCDecoderError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(chunk.frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        chunk.left.withUnsafeBufferPointer { source in
            left.update(from: source.baseAddress!, count: chunk.frameCount)
        }
        chunk.right.withUnsafeBufferPointer { source in
            right.update(from: source.baseAddress!, count: chunk.frameCount)
        }

        if let totalFrames, !decoder.appliesFadeInternally, fadeFrameCount > 0 {
            applyExternalFade(
                to: buffer,
                frameCount: chunk.frameCount,
                chunkStartFrame: chunkStartFrame,
                totalFrames: totalFrames
            )
        }

        return buffer
    }

    private var totalMilliseconds: Int {
        guard let totalFrames else { return Int.max }
        return Int((Double(totalFrames) / Double(decoder.sampleRate)) * 1_000)
    }

    private func applyExternalFade(
        to buffer: AVAudioPCMBuffer,
        frameCount: Int,
        chunkStartFrame: Int,
        totalFrames: Int
    ) {
        let fadeStartFrame = max(0, totalFrames - fadeFrameCount)
        guard chunkStartFrame + frameCount > fadeStartFrame else { return }

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for frameOffset in 0..<frameCount {
            let absoluteFrame = chunkStartFrame + frameOffset
            guard absoluteFrame >= fadeStartFrame else { continue }

            let remainingFrames = max(totalFrames - absoluteFrame, 0)
            let gain = Float(remainingFrames) / Float(max(fadeFrameCount, 1))
            left[frameOffset] *= gain
            right[frameOffset] *= gain
        }
    }
}

final class SPCDecoder {
    let sampleRate: Int
    private let trackIndex: Int
    private var emu: OpaquePointer?

    init(track: TrackItem, sampleRate: Int) throws {
        self.sampleRate = sampleRate
        self.trackIndex = max(0, track.trackIndex)
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)

        var created: OpaquePointer?
        try Self.throwIfNeeded(gme_open_file(fileURL.path, &created, Int32(sampleRate)))
        emu = created

        guard let emu else {
            throw SPCDecoderError.initializationFailed
        }

        try Self.throwIfNeeded(gme_start_track(emu, Int32(self.trackIndex)))
    }

    deinit {
        if let emu {
            gme_delete(emu)
        }
    }

    func metadata() throws -> TrackMetadata {
        guard let emu else {
            throw SPCDecoderError.initializationFailed
        }

        var infoPtr: UnsafeMutablePointer<gme_info_t>?
        try Self.throwIfNeeded(gme_track_info(emu, &infoPtr, Int32(trackIndex)))

        guard let infoPtr else {
            throw SPCDecoderError.metadataUnavailable
        }

        defer { gme_free_info(infoPtr) }

        let info = infoPtr.pointee
        return TrackMetadata(
            game: Self.string(from: info.game),
            song: Self.string(from: info.song),
            system: Self.string(from: info.system),
            author: Self.string(from: info.author),
            comment: Self.string(from: info.comment),
            introLengthMs: Int(info.intro_length),
            loopLengthMs: Int(info.loop_length),
            playLengthMs: Int(info.play_length),
            fadeLengthMs: Int(info.fade_length)
        )
    }

    var playedFrames: Int {
        guard let emu else {
            return 0
        }

        return Int(gme_tell_samples(emu) / 2)
    }

    var trackEnded: Bool {
        guard let emu else { return true }
        return gme_track_ended(emu) != 0
    }

    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {
        guard let emu else { return }
        gme_set_autoload_playback_limit(emu, usesNativeEnding ? 1 : 0)
        gme_ignore_silence(emu, usesNativeEnding ? 0 : 1)
        if !usesNativeEnding {
            gme_set_fade_msecs(emu, Int32(loopSeconds * 1_000), Int32(fadeSeconds * 1_000))
        }
    }

    func seek(toMilliseconds milliseconds: Int) throws {
        guard let emu else {
            throw SPCDecoderError.initializationFailed
        }

        try Self.throwIfNeeded(gme_seek(emu, Int32(milliseconds)))
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let emu else {
            throw SPCDecoderError.initializationFailed
        }

        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        var interleaved = [Int16](repeating: 0, count: frameCount * 2)

        try Self.throwIfNeeded(gme_play(emu, Int32(frameCount * 2), &interleaved))

        for frame in 0..<frameCount {
            let sourceIndex = frame * 2
            left[frame] = Float(interleaved[sourceIndex]) / Float(Int16.max)
            right[frame] = Float(interleaved[sourceIndex + 1]) / Float(Int16.max)
        }

        return DecodedChunk(left: left, right: right, frameCount: frameCount)
    }

    static func throwIfNeeded(_ error: gme_err_t?) throws {
        if let error {
            throw SPCDecoderError.library(String(cString: error))
        }
    }

    static func string(from pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        let value = String(cString: pointer)
        return value == "?" ? "" : value
    }
}

final class SPCFileInspector {
    private var emu: OpaquePointer?

    init(fileURL: URL) throws {
        var created: OpaquePointer?
        try SPCDecoder.throwIfNeeded(gme_open_file(fileURL.path, &created, Int32(gme_info_only)))
        emu = created

        guard emu != nil else {
            throw SPCDecoderError.initializationFailed
        }
    }

    deinit {
        if let emu {
            gme_delete(emu)
        }
    }

    var trackCount: Int {
        guard let emu else { return 0 }
        return Int(gme_track_count(emu))
    }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard let emu else {
            throw SPCDecoderError.initializationFailed
        }

        var infoPtr: UnsafeMutablePointer<gme_info_t>?
        try SPCDecoder.throwIfNeeded(gme_track_info(emu, &infoPtr, Int32(trackIndex)))

        guard let infoPtr else {
            throw SPCDecoderError.metadataUnavailable
        }

        defer { gme_free_info(infoPtr) }

        let info = infoPtr.pointee
        return TrackMetadata(
            game: SPCDecoder.string(from: info.game),
            song: SPCDecoder.string(from: info.song),
            system: SPCDecoder.string(from: info.system),
            author: SPCDecoder.string(from: info.author),
            comment: SPCDecoder.string(from: info.comment),
            introLengthMs: Int(info.intro_length),
            loopLengthMs: Int(info.loop_length),
            playLengthMs: Int(info.play_length),
            fadeLengthMs: Int(info.fade_length)
        )
    }
}

struct DecodedChunk {
    let left: [Float]
    let right: [Float]
    let frameCount: Int
}

enum SPCDecoderError: LocalizedError {
    case initializationFailed
    case metadataUnavailable
    case bufferCreationFailed
    case library(String)

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "The playback decoder failed to initialize this track."
        case .metadataUnavailable:
            return "Track metadata could not be read."
        case .bufferCreationFailed:
            return "The player could not allocate an audio buffer."
        case .library(let message):
            return message
        }
    }
}

struct PlaybackPlan: Equatable, Sendable {
    let preFadeSeconds: Int
    let fadeSeconds: Int
    let totalSeconds: Int
    let usesNativeEnding: Bool
}

struct PlaybackStatusSnapshot: Sendable {
    let currentTrackID: TrackItem.ID?
    let isPlaying: Bool
    let elapsedSeconds: TimeInterval
}
