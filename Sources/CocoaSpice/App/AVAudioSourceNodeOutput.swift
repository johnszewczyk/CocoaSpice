@preconcurrency import AVFoundation
import Foundation

final class AVAudioSourceNodeOutput: @unchecked Sendable, NativeAudioOutput {
    let sampleRate: Double
    let channels: AVAudioChannelCount
    let ringBuffer: RealtimePCMFrameRingBuffer
    private let transportEnvelope: RealtimePCMTransportEnvelope

    private let engine = AVAudioEngine()
    private let sourceNode: AVAudioSourceNode
    private let equalizerNode: AVAudioUnitEQ
    private let format: AVAudioFormat
    let primeFrameCount: Int
    private var transportState: PlaybackTransportState = .stopped
    private var outputState: NativeAudioOutputState = .stopped
    private var trackLoaded = false
    private var decodeError: String?
    private var reachedEnd = false
    private var generation = 0
    private var configurationChangeObserver: NSObjectProtocol?
    private var spectrumTapInstalled = false
    private var monoEnabled = false
    private var appVolume: Float = 1
    private let transitionDuration: TimeInterval = 0.024

    init(
        sampleRate: Double = 44_100,
        channels: AVAudioChannelCount = 2,
        capacityFrames: Int = 88_200,
        primeFrameCount: Int = 8_192
    ) throws {
        guard sampleRate > 0,
              channels == 2,
              primeFrameCount > 0,
              primeFrameCount <= capacityFrames else {
            throw AVAudioSourceNodeOutputError.invalidConfiguration
        }

        self.sampleRate = sampleRate
        self.channels = channels
        self.ringBuffer = try RealtimePCMFrameRingBuffer(capacityFrames: capacityFrames)
        self.transportEnvelope = try RealtimePCMTransportEnvelope()
        self.primeFrameCount = primeFrameCount
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ) else {
            throw AVAudioSourceNodeOutputError.invalidFormat
        }
        self.format = format
        self.equalizerNode = AVAudioUnitEQ(numberOfBands: AudioEqualizer.bandFrequencies.count)

        let ringBuffer = self.ringBuffer
        let transportEnvelope = self.transportEnvelope
        self.sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let requestedFrames = Int(frameCount)
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let leftData = buffers[0].mData,
                  let rightData = buffers[1].mData else {
                return noErr
            }

            let left = UnsafeMutableBufferPointer(
                start: leftData.assumingMemoryBound(to: Float.self),
                count: requestedFrames
            )
            let right = UnsafeMutableBufferPointer(
                start: rightData.assumingMemoryBound(to: Float.self),
                count: requestedFrames
            )
            let suppliedFrames = ringBuffer.read(left: left, right: right)
            if suppliedFrames < requestedFrames {
                left[suppliedFrames..<requestedFrames].initialize(repeating: 0)
                right[suppliedFrames..<requestedFrames].initialize(repeating: 0)
            }
            transportEnvelope.apply(left: left, right: right)
            return noErr
        }

        for (band, frequency) in zip(equalizerNode.bands, AudioEqualizer.bandFrequencies) {
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1
            band.gain = 0
            band.bypass = true
        }
        equalizerNode.bypass = true
        engine.attach(sourceNode)
        engine.attach(equalizerNode)
        engine.connect(sourceNode, to: equalizerNode, format: format)
        engine.connect(equalizerNode, to: engine.mainMixerNode, format: format)
    }

    deinit {
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
        }
    }

    func setSpectrumTap(
        bufferSize: AVAudioFrameCount,
        handler: @escaping (AVAudioPCMBuffer, AVAudioTime?) -> Void
    ) {
        guard !spectrumTapInstalled else { return }
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: mixerFormat,
            block: handler
        )
        spectrumTapInstalled = true
    }

    func removeSpectrumTap() {
        guard spectrumTapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        spectrumTapInstalled = false
    }

    func setEqualizer(enabled: Bool, bandGains: [Float]) {
        for (index, band) in equalizerNode.bands.enumerated() {
            band.gain = AudioEqualizer.clampedGain(bandGains[safe: index] ?? 0)
            band.bypass = !enabled
        }
        equalizerNode.bypass = !enabled
    }

    func setAppVolume(_ volume: Float) {
        // This is CocoaSpice's stock output volume (0–100%). It never calls
        // system-volume APIs, so hardware volume keys continue to control macOS.
        appVolume = AudioOutputVolume.clamped(volume)
        applyOutputGain()
    }

    /// Keep abrupt stream/graph replacements out of the audible path. The
    /// envelope runs sample-by-sample in the source-node render callback;
    /// this method only publishes its atomic target and waits for silence
    /// before the serial session tears down PCM or the graph.
    func duckForTransition() {
        guard engine.isRunning else {
            transportEnvelope.set(0)
            return
        }
        transportEnvelope.ramp(to: 0, overFrames: transitionFrameCount)
        waitForTransitionSilence()
    }

    func restoreAfterTransition() {
        transportEnvelope.ramp(to: 1, overFrames: transitionFrameCount)
    }

    /// A musical skip fade deliberately leaves the live decoder, ring, and
    /// output graph running. The caller owns the later adjacent-track change.
    func fadeLiveOutput(duration: TimeInterval) {
        guard engine.isRunning else { return }
        let frames = max(1, Int((sampleRate * max(0, duration)).rounded()))
        transportEnvelope.ramp(to: 0, overFrames: frames)
    }

    private func applyOutputGain() {
        engine.mainMixerNode.outputVolume = appVolume
    }

    private var transitionFrameCount: Int {
        max(1, Int((sampleRate * transitionDuration).rounded()))
    }

    private func waitForTransitionSilence() {
        let maximumWaitMicroseconds = UInt32((transitionDuration + 0.040) * 1_000_000)
        var waitedMicroseconds: UInt32 = 0
        while transportEnvelope.remainingFrames > 0, waitedMicroseconds < maximumWaitMicroseconds {
            usleep(1_000)
            waitedMicroseconds += 1_000
        }
        // A route change can halt callbacks while the output is being
        // replaced. The next source must still begin muted in that case.
        if transportEnvelope.remainingFrames > 0 {
            transportEnvelope.set(0)
        }
    }

    func setMonoEnabled(_ enabled: Bool) {
        monoEnabled = enabled
    }

    func setConfigurationChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in
            handler()
        }
    }

    var snapshot: NativeAudioOutputSnapshot {
        NativeAudioOutputSnapshot(
            transportState: transportState,
            outputState: outputState,
            trackLoaded: trackLoaded,
            decodeError: decodeError,
            reachedEnd: reachedEnd,
            sampleRate: Int(sampleRate),
            channelCount: Int(channels),
            bufferedFrames: Int64(ringBuffer.bufferedFrames),
            ringBufferFrames: Int64(ringBuffer.capacityFrames),
            framesRequested: ringBuffer.framesRequested,
            framesSupplied: ringBuffer.framesRead,
            underrunCount: ringBuffer.underrunCount,
            clippedSampleCount: ringBuffer.clippedSampleCount,
            positionFrames: ringBuffer.framesRead,
            generation: generation,
            engineIsRunning: engine.isRunning
        )
    }

    func enqueue(
        left: UnsafeBufferPointer<Float>,
        right: UnsafeBufferPointer<Float>
    ) -> Int {
        monoEnabled
            ? ringBuffer.writeMonoFromStereo(left: left, right: right)
            : ringBuffer.write(left: left, right: right)
    }

    func markTrackLoaded(generation: Int) {
        self.generation = generation
        trackLoaded = true
        reachedEnd = false
        decodeError = nil
        transportState = .loading
        outputState = .stopped
    }

    func markReachedEnd() {
        reachedEnd = true
    }

    func start() throws {
        guard trackLoaded else {
            throw AVAudioSourceNodeOutputError.noTrackLoaded
        }
        guard ringBuffer.bufferedFrames >= primeFrameCount else {
            outputState = .primed
            throw AVAudioSourceNodeOutputError.insufficientPriming
        }
        if !engine.isRunning {
            try engine.start()
        }
        outputState = .running
        transportState = .playing
    }

    func pause() {
        engine.pause()
        outputState = .primed
        transportState = .paused
    }

    func finish() {
        engine.pause()
        outputState = .stopped
        transportState = .ended
    }

    func prepareForRestart() {
        // A pause preserves AVAudioEngine's render-ahead state. On the next
        // start, that state can consume freshly queued frames before they are
        // audible, which makes a new track appear to start late. A full stop
        // resets the graph's render boundary at every track/seek restart.
        engine.stop()
        engine.reset()
        ringBuffer.clear()
        outputState = .stopped
        transportState = .stopped
    }

    /// Normal track and seek replacement keeps the output device alive. The
    /// render callback continues to receive silence while the next stream is
    /// primed, avoiding a Core Audio close/reopen discontinuity.
    func prepareForWarmReplacement() {
        ringBuffer.clear()
        outputState = .stopped
        transportState = .stopped
    }

    func stop() {
        engine.stop()
        engine.reset()
        ringBuffer.clear()
        outputState = .stopped
        transportState = .stopped
    }

    func clear() {
        ringBuffer.clear()
        generation += 1
        reachedEnd = false
        outputState = .stopped
        transportState = .stopped
    }
}

enum AudioEqualizer {
    static let bandFrequencies: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    static let gainRange: ClosedRange<Float> = -12...12

    static func clampedGain(_ gain: Float) -> Float {
        min(max(gain, gainRange.lowerBound), gainRange.upperBound)
    }
}

enum AudioOutputVolume {
    static let range: ClosedRange<Float> = 0...1

    static func clamped(_ value: Float) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum AVAudioSourceNodeOutputError: LocalizedError {
    case invalidConfiguration
    case invalidFormat
    case noTrackLoaded
    case insufficientPriming

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The native audio output configuration is invalid."
        case .invalidFormat:
            return "The native audio output format could not be created."
        case .noTrackLoaded:
            return "The native audio output cannot start without a loaded track."
        case .insufficientPriming:
            return "The native audio output is waiting for its minimum PCM prime level."
        }
    }
}
