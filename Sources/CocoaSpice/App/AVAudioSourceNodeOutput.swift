@preconcurrency import AVFoundation
import Foundation

final class AVAudioSourceNodeOutput: @unchecked Sendable, NativeAudioOutput {
    let sampleRate: Double
    let channels: AVAudioChannelCount
    let ringBuffer: RealtimePCMFrameRingBuffer

    private let engine = AVAudioEngine()
    private let sourceNode: AVAudioSourceNode
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
        self.primeFrameCount = primeFrameCount
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ) else {
            throw AVAudioSourceNodeOutputError.invalidFormat
        }
        self.format = format

        let ringBuffer = self.ringBuffer
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
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
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
            generation: generation
        )
    }

    func enqueue(
        left: UnsafeBufferPointer<Float>,
        right: UnsafeBufferPointer<Float>
    ) -> Int {
        ringBuffer.write(left: left, right: right)
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
        ringBuffer.clear()
        outputState = .stopped
        transportState = .stopped
    }

    func stop() {
        engine.stop()
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
