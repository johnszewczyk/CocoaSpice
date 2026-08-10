@preconcurrency import AVFoundation
import Accelerate
import Foundation
import CGME

final class PlaybackEngine: @unchecked Sendable {
    private let sampleRate: Double = 44_100
    private let channels: AVAudioChannelCount = 2
    private let chunkFrameCount = 2_048
    private let queue = DispatchQueue(label: "CocoaSpice.playback", qos: .userInitiated)
    private let nativeSession: NativePlaybackSession
    private let requestLock = NSLock()
    private var spectrumAnalyzer: SpectrumBandAnalyzer
    private var currentPlaybackDuration: TimeInterval = 0
    private var spectrumLevelHandler: (@Sendable ([Float]) -> Void)?
    private var spectrumEnabled = true
    private var equalizerEnabled = false
    private var equalizerBandGains = AudioEqualizer.bandFrequencies.map { _ in Float.zero }
    private var appVolume: Float = 1
    private var monoEnabled = false
    private var playbackStateHandler: (@Sendable (PlaybackStatusSnapshot) -> Void)?
    private var latestPlaybackRequest = 0

    private(set) var currentTrack: TrackItem?
    private(set) var isPlaying = false
    private(set) var currentPlaybackPlan = PlaybackPlan(preFadeSeconds: 150, fadeSeconds: 6, totalSeconds: 156, usesNativeEnding: false, isLongPlay: false)

    init() {
        spectrumAnalyzer = SpectrumBandAnalyzer(sampleRate: Float(sampleRate), bandCount: SpectrumBandCount.defaultValue)
        nativeSession = try! NativePlaybackSession(
            sampleRate: sampleRate,
            channels: channels,
            chunkFrameCount: chunkFrameCount
        )
        nativeSession.setSpectrumHandler { [weak self] buffer, _ in
            self?.handleSpectrumBuffer(buffer)
        }
        nativeSession.setCompletionHandler { [weak self] generation in
            guard let self else { return }
            self.queue.async { [weak self] in
                self?.handleNativeCompletion(generation: generation)
            }
        }
    }

    func setSpectrumLevelHandler(_ handler: (@Sendable ([Float]) -> Void)?) {
        queue.async {
            self.spectrumLevelHandler = handler
        }
    }

    func setSpectrumEnabled(_ enabled: Bool) {
        queue.async {
            self.spectrumEnabled = enabled
            self.nativeSession.setSpectrumEnabled(enabled)
            if !enabled {
                self.spectrumAnalyzer.reset()
            }
        }
    }

    func setSpectrumBandCount(_ bandCount: Int) {
        queue.async {
            let clamped = SpectrumBandCount.clamped(bandCount)
            guard self.spectrumAnalyzer.bandCount != clamped else { return }
            self.spectrumAnalyzer = SpectrumBandAnalyzer(sampleRate: Float(self.sampleRate), bandCount: clamped)
            self.spectrumLevelHandler?(Array(repeating: 0, count: clamped))
        }
    }

    func setEqualizer(enabled: Bool, bandGains: [Float]) {
        queue.async {
            self.equalizerEnabled = enabled
            self.equalizerBandGains = bandGains
            self.nativeSession.setEqualizer(enabled: enabled, bandGains: bandGains)
        }
    }

    func setAppVolume(_ volume: Float) {
        queue.async {
            self.appVolume = AudioOutputVolume.clamped(volume)
            self.nativeSession.setAppVolume(self.appVolume)
        }
    }

    func setMonoEnabled(_ enabled: Bool) {
        queue.async {
            self.monoEnabled = enabled
            self.nativeSession.setMonoEnabled(enabled)
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
            return try self.loadTrack(
                track: track,
                plan: plan,
                resumeAt: 0
            )
        }
    }

    /// A timing-mode change can require reopening a decoder to change its
    /// native loop policy. Preserve the rendered position rather than restart
    /// the track from zero.
    func reconfigureCurrentTrack(plan: PlaybackPlan) async throws -> TrackMetadata {
        try await enqueue {
            guard let track = self.currentTrack else {
                throw NSError(domain: "PlaybackEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "No track is loaded."])
            }
            let snapshot = self.currentSnapshot()
            let metadata = try self.loadTrack(
                track: track,
                plan: plan,
                resumeAt: snapshot.elapsedSeconds,
                autoplay: snapshot.isPlaying
            )
            self.isPlaying = snapshot.isPlaying
            self.publishPlaybackState()
            return metadata
        }
    }

    private func isLatestPlaybackRequest(_ requestID: Int) -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return requestID == latestPlaybackRequest
    }

    func togglePause() async -> Bool {
        await enqueue {
            do {
                self.isPlaying = try self.nativeSession.togglePause()
            } catch {
                self.resetPlaybackState()
            }
            self.publishPlaybackState()
            return self.isPlaying
        }
    }

    func stopPlayback() async {
        await enqueue {
            self.resetPlaybackState()
            ZipArchiveSupport.discardDisposablePlaybackMaterialization()
        }
    }

    func stop() async {
        await stopPlayback()
    }

    func beginFadedSkip(duration: TimeInterval) async -> Int? {
        await enqueue {
            self.nativeSession.beginFadedSkip(duration: duration)
        }
    }

    func isCurrentGeneration(_ generation: Int) async -> Bool {
        await enqueue {
            self.nativeSession.isCurrentGeneration(generation)
        }
    }

    func statusSnapshot() async -> PlaybackStatusSnapshot {
        await enqueue {
            self.currentSnapshot()
        }
    }

    func diagnosticsSnapshot() -> PlaybackDiagnosticsSnapshot {
        nativeSession.diagnosticsSnapshot()
    }

    func currentTrackID() async -> TrackItem.ID? {
        await enqueue {
            self.currentTrack?.id
        }
    }

    func seek(to seconds: TimeInterval) async throws {
        try await enqueue {
            guard self.currentTrack != nil else { return }
            let clampedSeconds: TimeInterval
            if self.currentPlaybackPlan.usesNativeEnding {
                clampedSeconds = max(0, seconds)
            } else {
                clampedSeconds = max(0, min(seconds, self.currentPlaybackDuration))
            }
            try self.nativeSession.seek(to: clampedSeconds)
            self.isPlaying = self.nativeSession.statusSnapshot().isPlaying
            self.publishPlaybackState()
        }
    }

    private func loadTrack(
        track: TrackItem,
        plan: PlaybackPlan,
        resumeAt requestedSeconds: TimeInterval,
        autoplay: Bool = true
    ) throws -> TrackMetadata {
        currentTrack = track
        currentPlaybackPlan = plan
        currentPlaybackDuration = TimeInterval(plan.totalSeconds)

        let clampedResume: TimeInterval
        if plan.usesNativeEnding {
            clampedResume = max(0, requestedSeconds)
        } else {
            clampedResume = max(0, min(requestedSeconds, currentPlaybackDuration))
        }
        let metadata = try nativeSession.load(
            track: track,
            plan: plan,
            resumeAt: clampedResume,
            autoplay: autoplay
        )
        isPlaying = autoplay
        publishPlaybackState()
        return metadata
    }

    private func resetPlaybackState() {
        nativeSession.stop()
        isPlaying = false
        currentTrack = nil
        currentPlaybackDuration = 0
        spectrumAnalyzer.reset()
        spectrumLevelHandler?(Array(repeating: 0, count: spectrumAnalyzer.bandCount))
        publishPlaybackState()
    }

    private func publishPlaybackState() {
        playbackStateHandler?(currentSnapshot())
    }

    private func currentSnapshot() -> PlaybackStatusSnapshot {
        nativeSession.statusSnapshot()
    }

    private func handleSpectrumBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isPlaying, spectrumEnabled else { return }
        guard let levels = spectrumAnalyzer.process(buffer: buffer) else { return }
        spectrumLevelHandler?(levels)
    }

    private func handleNativeCompletion(generation: Int) {
        guard nativeSession.isCurrentGeneration(generation) else { return }
        isPlaying = false
        spectrumAnalyzer.reset()
        spectrumLevelHandler?(Array(repeating: 0, count: spectrumAnalyzer.bandCount))
        publishPlaybackState()
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
    // Ten octave intervals from 20 Hz through 20.48 kHz. The selectable 10,
    // 20, and 40 displays therefore mean 1, 2, and 4 bands per octave; each
    // higher-detail setting splits every prior band at its log midpoint.
    private static let minimumBandFrequency: Float = 20
    private static let maximumBandFrequency: Float = 20_480
    private static let displayFloorDB: Float = -78
    private static let displayCeilingDB: Float = -6

    private let sampleRate: Float
    let bandCount: Int
    // Log-spaced centers over a chiptune-oriented range.
    // This preserves an orderly analyzer layout while biasing the visible activity
    // toward the region that tends to matter most for retro game music.
    // Equal spacing in log frequency gives each band the same relative width,
    // matching how real EQ bands are distributed across octaves.
    private let bandEdges: [(lower: Float, upper: Float)]
    // 4,096 samples give 10.77 Hz bins at 44.1 kHz. Unlike a center probe,
    // bin powers are integrated across each fractional-octave band.
    private let analysisFrameCount = 4_096
    private let fftLog2n: vDSP_Length = 12
    private let minimumUpdateInterval: TimeInterval = 1.0 / 10.0
    private var analysisBuffer = Array(repeating: Float.zero, count: 4_096)
    private var fftReal = Array(repeating: Float.zero, count: 2_048)
    private var fftImaginary = Array(repeating: Float.zero, count: 2_048)
    private let fftSetup: FFTSetup
    private var lastPublishUptime: TimeInterval = 0

    init(sampleRate: Float, bandCount: Int) {
        self.sampleRate = sampleRate
        self.bandCount = SpectrumBandCount.clamped(bandCount)
        guard let fftSetup = vDSP_create_fftsetup(fftLog2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Could not create spectrum FFT setup")
        }
        self.fftSetup = fftSetup
        let bandRatio = pow(
            Self.maximumBandFrequency / Self.minimumBandFrequency,
            1 / Float(self.bandCount)
        )
        bandEdges = (0..<self.bandCount).map { index in
            let lower = Self.minimumBandFrequency * pow(bandRatio, Float(index))
            let upper = Self.minimumBandFrequency * pow(bandRatio, Float(index + 1))
            return (lower: lower, upper: upper)
        }
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
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
        for frame in 0..<frameCount {
            var monoSample: Float = 0
            for channel in 0..<channelCount {
                monoSample += channelData[channel][frame]
            }
            monoSample *= inverseChannelCount
            // A Hann window suppresses spectral leakage: a strong tone no
            // longer paints every adjacent display band at nearly the same
            // height just because it cuts across the sample boundary.
            let window = frameCount > 1
                ? 0.5 - (0.5 * cos((2 * Float.pi * Float(frame)) / Float(frameCount - 1)))
                : 1
            analysisBuffer[frame] = monoSample * window
        }

        let binFrequency = sampleRate / Float(frameCount)
        let powerScale = 1.0 / Float(frameCount * frameCount)
        var levels = Array(repeating: Float.zero, count: bandCount)
        analysisBuffer.withUnsafeBufferPointer { input in
            fftReal.withUnsafeMutableBufferPointer { real in
                fftImaginary.withUnsafeMutableBufferPointer { imaginary in
                    guard let inputBase = input.baseAddress,
                          let realBase = real.baseAddress,
                          let imaginaryBase = imaginary.baseAddress else { return }
                    var split = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)
                    inputBase.withMemoryRebound(to: DSPComplex.self, capacity: frameCount / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(frameCount / 2))
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, fftLog2n, FFTDirection(FFT_FORWARD))

                    for index in bandEdges.indices {
                        let edge = bandEdges[index]
                        // An FFT bin represents a frequency cell centered on
                        // its nominal frequency, not a single mathematical
                        // point.  Assign its power by overlap with the display
                        // band.  Whole-bin assignment left narrow 40-band
                        // intervals between adjacent low-frequency bins empty.
                        let firstBin = max(1, Int(floor(edge.lower / binFrequency)))
                        let lastBin = min(frameCount / 2 - 1, Int(ceil(edge.upper / binFrequency)))
                        guard firstBin <= lastBin else { continue }
                        var power: Float = 0
                        for bin in firstBin...lastBin {
                            let binLower = (Float(bin) - 0.5) * binFrequency
                            let binUpper = (Float(bin) + 0.5) * binFrequency
                            let overlap = max(0, min(edge.upper, binUpper) - max(edge.lower, binLower))
                            guard overlap > 0 else { continue }
                            let binPower = (real[bin] * real[bin]) + (imaginary[bin] * imaginary[bin])
                            power += binPower * (overlap / binFrequency)
                        }
                        let db = 10 * log10f(max(power * powerScale, Float.leastNonzeroMagnitude))
                        levels[index] = min(1, max(0, (db - Self.displayFloorDB) / (Self.displayCeilingDB - Self.displayFloorDB)))
                    }
                }
            }
        }
        return levels
    }
}

/// Converts decoder-native stereo PCM into the playback engine's shared output clock.
///
/// vgmstream reports the real clock used by formats such as PlayStation CD-XA
/// (37,800 Hz).  The native output endpoint is fixed at 44.1 kHz, so copying
/// those frames directly would make them play 44,100 / 37,800 times too fast.
final class LinearStereoResampler {
    private let sourceFramesPerOutputFrame: Double
    private var sourceLeft: [Float] = []
    private var sourceRight: [Float] = []
    private var sourcePosition = 0.0

    init(sourceSampleRate: Int, outputSampleRate: Int) {
        sourceFramesPerOutputFrame = Double(max(sourceSampleRate, 1)) /
            Double(max(outputSampleRate, 1))
    }

    func reset() {
        sourceLeft.removeAll(keepingCapacity: true)
        sourceRight.removeAll(keepingCapacity: true)
        sourcePosition = 0
    }

    func append(_ chunk: DecodedChunk) {
        guard chunk.frameCount > 0 else { return }
        sourceLeft.append(contentsOf: chunk.left.prefix(chunk.frameCount))
        sourceRight.append(contentsOf: chunk.right.prefix(chunk.frameCount))
    }

    func render(maximumFrames: Int, endOfInput: Bool) -> DecodedChunk {
        guard maximumFrames > 0 else {
            return DecodedChunk(left: [], right: [], frameCount: 0)
        }

        var left: [Float] = []
        var right: [Float] = []
        left.reserveCapacity(maximumFrames)
        right.reserveCapacity(maximumFrames)

        while left.count < maximumFrames {
            let index = Int(sourcePosition)
            guard index < sourceLeft.count else { break }

            let nextIndex = index + 1
            guard nextIndex < sourceLeft.count || endOfInput else { break }

            let interpolation = Float(sourcePosition - Double(index))
            let upperIndex = min(nextIndex, sourceLeft.count - 1)
            left.append(sourceLeft[index] + ((sourceLeft[upperIndex] - sourceLeft[index]) * interpolation))
            right.append(sourceRight[index] + ((sourceRight[upperIndex] - sourceRight[index]) * interpolation))
            sourcePosition += sourceFramesPerOutputFrame
        }

        discardConsumedFrames()
        return DecodedChunk(left: left, right: right, frameCount: left.count)
    }

    private func discardConsumedFrames() {
        // Keep the frame immediately before the fractional read position so
        // interpolation remains continuous across future decoder chunks.
        let discardCount = max(0, Int(sourcePosition) - 1)
        guard discardCount > 0 else { return }
        sourceLeft.removeFirst(discardCount)
        sourceRight.removeFirst(discardCount)
        sourcePosition -= Double(discardCount)
    }
}

final class PlaybackStreamSession {
    let metadata: TrackMetadata
    let totalFrames: Int?

    private let decoder: any AudioTrackDecoder
    private let chunkFrameCount: Int
    private let fadeFrameCount: Int
    private let outputFormat: AVAudioFormat
    private let outputSampleRate: Int
    private let resampler: LinearStereoResampler?
    private var outputFramesProduced = 0

    init(
        track: TrackItem,
        sampleRate: Int,
        totalSeconds: Int,
        loopSeconds: Int,
        fadeSeconds: Int,
        isLongPlay: Bool,
        chunkFrameCount: Int
    ) throws {
        decoder = try PlaybackDecoderFactory.makeDecoder(track: track, sampleRate: sampleRate)
        metadata = try decoder.metadata()
        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: 2
        ) else {
            throw SPCDecoderError.bufferCreationFailed
        }
        self.outputFormat = outputFormat
        outputSampleRate = sampleRate
        resampler = decoder.sampleRate == sampleRate
            ? nil
            : LinearStereoResampler(
                sourceSampleRate: decoder.sampleRate,
                outputSampleRate: sampleRate
            )
        totalFrames = totalSeconds > 0 ? max(totalSeconds * sampleRate, 1) : nil
        self.chunkFrameCount = chunkFrameCount
        fadeFrameCount = max(0, fadeSeconds * sampleRate)
        decoder.setLongPlayEnabled(isLongPlay)
        decoder.configurePlayback(
            loopSeconds: loopSeconds,
            fadeSeconds: fadeSeconds,
            usesNativeEnding: totalSeconds <= 0
        )
    }

    func seek(to seconds: TimeInterval) throws {
        guard seconds > 0 else { return }
        let clampedMilliseconds = max(0, min(Int(seconds * 1_000), totalMilliseconds))
        try decoder.seek(toMilliseconds: clampedMilliseconds)
        resampler?.reset()
        outputFramesProduced = min(
            totalFrames ?? .max,
            Int((Double(clampedMilliseconds) / 1_000) * Double(outputSampleRate))
        )
    }

    func setSuspended(_ suspended: Bool) {
        decoder.setSuspended(suspended)
    }

    func makeNextBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount
    ) throws -> AVAudioPCMBuffer? {
        guard channels == 2 else { throw SPCDecoderError.bufferCreationFailed }

        if let totalFrames {
            guard outputFramesProduced < totalFrames else { return nil }
        }

        let frameCount: Int
        if let totalFrames {
            frameCount = min(chunkFrameCount, totalFrames - outputFramesProduced)
        } else {
            frameCount = chunkFrameCount
        }
        let chunkStartFrame = outputFramesProduced
        let chunk = try decodeOutputFrames(frameCount: frameCount)
        guard chunk.frameCount > 0 else { return nil }
        outputFramesProduced += chunk.frameCount

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
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
        return Int((Double(totalFrames) / Double(outputSampleRate)) * 1_000)
    }

    private func decodeOutputFrames(frameCount: Int) throws -> DecodedChunk {
        guard let resampler else {
            return try decoder.decode(frameCount: frameCount)
        }

        var left: [Float] = []
        var right: [Float] = []
        left.reserveCapacity(frameCount)
        right.reserveCapacity(frameCount)

        while left.count < frameCount {
            let rendered = resampler.render(
                maximumFrames: frameCount - left.count,
                endOfInput: decoder.trackEnded
            )
            if rendered.frameCount > 0 {
                left.append(contentsOf: rendered.left)
                right.append(contentsOf: rendered.right)
                continue
            }

            guard !decoder.trackEnded else { break }
            let remainingOutputFrames = frameCount - left.count
            let sourceFrames = max(
                256,
                Int(ceil(
                    Double(remainingOutputFrames) * Double(decoder.sampleRate) /
                        Double(outputSampleRate)
                )) + 2
            )
            let sourceChunk = try decoder.decode(frameCount: sourceFrames)
            guard sourceChunk.frameCount > 0 else { break }
            resampler.append(sourceChunk)
        }

        return DecodedChunk(left: left, right: right, frameCount: left.count)
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
            left[frame] = PCMFloatConversion.normalized(interleaved[sourceIndex])
            right[frame] = PCMFloatConversion.normalized(interleaved[sourceIndex + 1])
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
    let isLongPlay: Bool
}

struct PlaybackStatusSnapshot: Sendable {
    let currentTrackID: TrackItem.ID?
    let isPlaying: Bool
    let elapsedSeconds: TimeInterval
    let reachedEnd: Bool
}
