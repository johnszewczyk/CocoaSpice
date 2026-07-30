@preconcurrency import AVFoundation
import Foundation

final class NativePlaybackSession: @unchecked Sendable {
    private let sampleRate: Double
    private let channels: AVAudioChannelCount
    private let chunkFrameCount: Int
    private let output: AVAudioSourceNodeOutput
    private let refillQueue = DispatchQueue(label: "CocoaSpice.native-playback-refill", qos: .userInitiated)
    private var refillTimer: DispatchSourceTimer?
    private var stream: PlaybackStreamSession?
    private var currentTrack: TrackItem?
    private var generation = 0
    private var finishedGeneration: Int?
    private var completionHandler: (@Sendable (Int) -> Void)?

    init(
        sampleRate: Double = 44_100,
        channels: AVAudioChannelCount = 2,
        chunkFrameCount: Int = 4_096
    ) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        self.chunkFrameCount = chunkFrameCount
        output = try AVAudioSourceNodeOutput(
            sampleRate: sampleRate,
            channels: channels
        )
        output.setConfigurationChangeHandler { [weak self] in
            self?.recoverFromConfigurationChange()
        }
    }

    func setSpectrumTap(
        bufferSize: AVAudioFrameCount,
        handler: @escaping (AVAudioPCMBuffer, AVAudioTime?) -> Void
    ) {
        output.setSpectrumTap(bufferSize: bufferSize, handler: handler)
    }

    func setSpectrumEnabled(_ enabled: Bool) {
        refillQueue.sync {
            if enabled {
                let handler = spectrumHandler
                // A 4,410-frame tap supplies a 4,096-point FFT window at
                // roughly 10 Hz; the display model draws its targets at 45 FPS.
                output.setSpectrumTap(bufferSize: 4_410) { buffer, time in
                    handler?(buffer, time)
                }
            } else {
                output.removeSpectrumTap()
            }
        }
    }

    func setEqualizer(enabled: Bool, bandGains: [Float]) {
        refillQueue.sync {
            output.setEqualizer(enabled: enabled, bandGains: bandGains)
        }
    }

    func setAppVolume(_ volume: Float) {
        refillQueue.sync {
            output.setAppVolume(volume)
        }
    }

    private var spectrumHandler: ((AVAudioPCMBuffer, AVAudioTime?) -> Void)?

    func setSpectrumHandler(_ handler: ((AVAudioPCMBuffer, AVAudioTime?) -> Void)?) {
        refillQueue.sync {
            spectrumHandler = handler
        }
    }

    func setCompletionHandler(_ handler: (@Sendable (Int) -> Void)?) {
        refillQueue.async {
            self.completionHandler = handler
        }
    }

    func load(
        track: TrackItem,
        plan: PlaybackPlan,
        resumeAt seconds: TimeInterval = 0,
        autoplay: Bool
    ) throws -> TrackMetadata {
        try refillQueue.sync {
            refillTimer?.cancel()
            refillTimer = nil
            output.prepareForRestart()
            // The 2SF player owns process-global DS state. Release the old
            // decoder before constructing its replacement, otherwise the old
            // decoder's teardown can corrupt the newly loaded DS core.
            self.stream = nil
            currentTrack = nil

            let stream = try PlaybackStreamSession(
                track: track,
                sampleRate: Int(sampleRate),
                totalSeconds: plan.usesNativeEnding ? 0 : plan.totalSeconds,
                loopSeconds: plan.preFadeSeconds,
                fadeSeconds: plan.fadeSeconds,
                isLongPlay: plan.isLongPlay,
                chunkFrameCount: chunkFrameCount
            )
            try stream.seek(to: seconds)

            generation += 1
            finishedGeneration = nil
            self.stream = stream
            currentTrack = track
            output.clear()
            output.markTrackLoaded(generation: generation)
            try refillTo(targetBufferedFrames: output.primeFrameCount)

            if autoplay {
                try output.start()
                startRefillTimer()
            } else {
                stream.setSuspended(true)
            }
            return stream.metadata
        }
    }

    func togglePause() throws -> Bool {
        try refillQueue.sync {
            let isPlaying = output.snapshot.transportState == .playing
            if isPlaying {
                output.pause()
                stream?.setSuspended(true)
                refillTimer?.cancel()
                refillTimer = nil
                return false
            }

            stream?.setSuspended(false)
            try output.start()
            startRefillTimer()
            return true
        }
    }

    func seek(to seconds: TimeInterval) throws {
        try refillQueue.sync {
            guard let stream else { return }
            let wasPlaying = output.snapshot.transportState == .playing
            output.prepareForRestart()
            generation += 1
            finishedGeneration = nil
            try stream.seek(to: seconds)
            if !wasPlaying {
                stream.setSuspended(true)
            }
            output.clear()
            output.markTrackLoaded(generation: generation)
            try refillTo(targetBufferedFrames: output.primeFrameCount)
            if wasPlaying {
                try output.start()
            }
        }
    }

    func stop() {
        refillQueue.sync {
            refillTimer?.cancel()
            refillTimer = nil
            generation += 1
            finishedGeneration = nil
            stream = nil
            currentTrack = nil
            output.stop()
        }
    }

    func statusSnapshot() -> PlaybackStatusSnapshot {
        refillQueue.sync {
            let snapshot = output.snapshot
            return PlaybackStatusSnapshot(
                currentTrackID: currentTrack?.id,
                isPlaying: snapshot.transportState == .playing,
                elapsedSeconds: PlaybackFrameAccounting.positionSeconds(
                    sessionStartFrame: 0,
                    framesSupplied: snapshot.framesSupplied,
                    sampleRate: Int(sampleRate)
                ),
                reachedEnd: snapshot.reachedEnd
            )
        }
    }

    func diagnosticsSnapshot() -> PlaybackDiagnosticsSnapshot {
        refillQueue.sync {
            let snapshot = output.snapshot
            return PlaybackDiagnosticsSnapshot(
                bufferedFrames: snapshot.bufferedFrames,
                ringBufferFrames: snapshot.ringBufferFrames,
                underrunCount: snapshot.underrunCount,
                clippedSampleCount: snapshot.clippedSampleCount,
                sampleRate: snapshot.sampleRate
            )
        }
    }

    func isCurrentGeneration(_ generation: Int) -> Bool {
        refillQueue.sync {
            output.snapshot.generation == generation
        }
    }

    private func startRefillTimer() {
        let timer = DispatchSource.makeTimerSource(queue: refillQueue)
        // The ring buffer holds about two seconds of audio. A 20 ms refill
        // cadence leaves ample headroom while avoiding needless wakeups.
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.refill()
        }
        refillTimer = timer
        timer.resume()
    }

    private func refill() {
        guard stream != nil else { return }

        do {
            try refillToHighWaterMark()
        } catch {
            output.stop()
            return
        }

        guard output.snapshot.reachedEnd,
              output.snapshot.bufferedFrames == 0,
              finishedGeneration != generation else {
            return
        }

        finishedGeneration = generation
        output.finish()
        completionHandler?(generation)
    }

    private func recoverFromConfigurationChange() {
        refillQueue.async {
            guard let stream = self.stream else { return }
            let wasPlaying = self.output.snapshot.transportState == .playing
            let position = self.output.snapshot.positionFrames
            let seconds = PlaybackFrameAccounting.positionSeconds(
                sessionStartFrame: 0,
                framesSupplied: position,
                sampleRate: Int(self.sampleRate)
            )

            do {
                self.output.stop()
                self.generation += 1
                self.finishedGeneration = nil
                try stream.seek(to: seconds)
                if !wasPlaying {
                    stream.setSuspended(true)
                }
                self.output.clear()
                self.output.markTrackLoaded(generation: self.generation)
                try self.refillTo(targetBufferedFrames: self.output.primeFrameCount)
                if wasPlaying {
                    try self.output.start()
                }
            } catch {
                self.output.stop()
            }
        }
    }

    private func refillToHighWaterMark() throws {
        let highWaterMark = Int(Double(output.ringBuffer.capacityFrames) * 0.75)
        try refillTo(targetBufferedFrames: highWaterMark)
    }

    private func refillTo(targetBufferedFrames: Int) throws {
        guard let stream else { return }

        while output.ringBuffer.bufferedFrames < targetBufferedFrames {
            guard let buffer = try stream.makeNextBuffer(
                sampleRate: sampleRate,
                channels: channels
            ) else {
                output.markReachedEnd()
                break
            }

            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0,
                  let channelData = buffer.floatChannelData else {
                break
            }

            let left = UnsafeBufferPointer(start: channelData[0], count: frameCount)
            let right = UnsafeBufferPointer(start: channelData[1], count: frameCount)
            let written = output.enqueue(left: left, right: right)
            if written < frameCount {
                break
            }
        }
    }
}
