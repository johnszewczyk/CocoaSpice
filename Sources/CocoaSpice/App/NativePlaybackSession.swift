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
    /// The ring buffer resets at each graph/decoder rebuild. Keep the musical
    /// timeline separately so a Long Play change cannot publish `0:00` and
    /// make the following change seek back to the beginning.
    private var sessionStartFrame: Int64 = 0
    private var finishedGeneration: Int?
    private var completionHandler: (@Sendable (Int) -> Void)?
    private let outputHeartbeat = PlaybackOutputHeartbeat()

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
                // roughly 10 Hz; the display model draws its targets at 60 FPS.
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

    func setMonoEnabled(_ enabled: Bool) {
        refillQueue.sync {
            output.setMonoEnabled(enabled)
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
            // Every new stream starts from a muted final mixer, including the
            // first one after launch or Stop. Starting a primed source at
            // unity can expose its first non-zero PCM sample as a pop.
            output.duckForTransition()
            refillTimer?.cancel()
            refillTimer = nil
            outputHeartbeat.reset(expectingRenderRequests: false)
            output.prepareForWarmReplacement()
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
            sessionStartFrame = Int64(max(0, (seconds * sampleRate).rounded()))
            finishedGeneration = nil
            self.stream = stream
            currentTrack = track
            output.clear()
            output.markTrackLoaded(generation: generation)
            try refillTo(targetBufferedFrames: output.primeFrameCount)

            if autoplay {
                try output.start()
                output.restoreAfterTransition()
                outputHeartbeat.reset(expectingRenderRequests: true)
                startRefillTimer()
            } else {
                stream.setSuspended(true)
                outputHeartbeat.reset(expectingRenderRequests: false)
            }
            return stream.metadata
        }
    }

    func togglePause() throws -> Bool {
        try refillQueue.sync {
            let isPlaying = output.snapshot.transportState == .playing
            if isPlaying {
                output.duckForTransition()
                output.pause()
                stream?.setSuspended(true)
                refillTimer?.cancel()
                refillTimer = nil
                outputHeartbeat.reset(expectingRenderRequests: false)
                return false
            }

            stream?.setSuspended(false)
            try output.start()
            output.restoreAfterTransition()
            outputHeartbeat.reset(expectingRenderRequests: true)
            startRefillTimer()
            return true
        }
    }

    func seek(to seconds: TimeInterval) throws {
        try refillQueue.sync {
            guard let stream else { return }
            let wasPlaying = output.snapshot.transportState == .playing
            if wasPlaying { output.duckForTransition() }
            outputHeartbeat.reset(expectingRenderRequests: false)
            output.prepareForWarmReplacement()
            generation += 1
            sessionStartFrame = Int64(max(0, (seconds * sampleRate).rounded()))
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
                output.restoreAfterTransition()
                outputHeartbeat.reset(expectingRenderRequests: true)
            } else {
                outputHeartbeat.reset(expectingRenderRequests: false)
            }
        }
    }

    func stop() {
        refillQueue.sync {
            if output.snapshot.transportState == .playing { output.duckForTransition() }
            refillTimer?.cancel()
            refillTimer = nil
            generation += 1
            finishedGeneration = nil
            stream = nil
            currentTrack = nil
            sessionStartFrame = 0
            output.stop()
            outputHeartbeat.reset(expectingRenderRequests: false)
        }
    }

    /// Begins a non-destructive musical fade of the current live source. The
    /// refill timer keeps decoding until the coordinator advances the queue.
    func beginFadedSkip(duration: TimeInterval) -> Int? {
        refillQueue.sync {
            guard output.snapshot.transportState == .playing else { return nil }
            output.fadeLiveOutput(duration: duration)
            return generation
        }
    }

    func statusSnapshot() -> PlaybackStatusSnapshot {
        refillQueue.sync {
            let snapshot = output.snapshot
            return PlaybackStatusSnapshot(
                currentTrackID: currentTrack?.id,
                isPlaying: snapshot.transportState == .playing,
                elapsedSeconds: PlaybackFrameAccounting.positionSeconds(
                    sessionStartFrame: sessionStartFrame,
                    framesSupplied: snapshot.framesSupplied,
                    sampleRate: Int(sampleRate)
                ),
                reachedEnd: snapshot.reachedEnd
            )
        }
    }

    func diagnosticsSnapshot() -> PlaybackDiagnosticsSnapshot {
        // This deliberately bypasses refillQueue. A blocked decoder must not
        // also hide the fact that the source node has stopped being serviced.
        let ringBuffer = output.ringBuffer
        return PlaybackDiagnosticsSnapshot(
            bufferedFrames: Int64(ringBuffer.bufferedFrames),
            ringBufferFrames: Int64(ringBuffer.capacityFrames),
            underrunCount: ringBuffer.underrunCount,
            clippedSampleCount: ringBuffer.clippedSampleCount,
            sampleRate: Int(sampleRate),
            outputHealth: outputHeartbeat.health(framesRequested: ringBuffer.framesRequested)
        )
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
            outputHeartbeat.reset(expectingRenderRequests: false)
            return
        }

        guard output.snapshot.reachedEnd,
              output.snapshot.bufferedFrames == 0,
              finishedGeneration != generation else {
            return
        }

        finishedGeneration = generation
        output.finish()
        outputHeartbeat.reset(expectingRenderRequests: false)
        completionHandler?(generation)
    }

    private func recoverFromConfigurationChange() {
        refillQueue.async {
            guard let stream = self.stream else { return }
            let wasPlaying = self.output.snapshot.transportState == .playing
            let resumeFrame = PlaybackFrameAccounting.positionFrames(
                sessionStartFrame: self.sessionStartFrame,
                framesSupplied: self.output.ringBuffer.framesRead
            )

            do {
                // An AVAudioEngine configuration change (usually sleep/wake or
                // an output-device change) invalidates the output graph, not
                // the decoder's current state. Seeking here is actively
                // harmful for emulated, indefinitely looping formats: a USF
                // seek renders every millisecond from the beginning, so an
                // hours-old Long Play session can monopolize this serial queue
                // indefinitely and strand the UI in a loading state.
                //
                // Keep the live decoder exactly where it is, discard the short
                // render-ahead buffer, then prime the rebuilt graph from the
                // decoder's current state. The only cost is up to the old
                // ring-buffer horizon (about two seconds), never elapsed-time
                // re-emulation.
                self.refillTimer?.cancel()
                self.refillTimer = nil
                if wasPlaying { self.output.duckForTransition() }
                self.output.prepareForRestart()
                self.generation += 1
                self.sessionStartFrame = resumeFrame
                self.finishedGeneration = nil
                stream.setSuspended(false)
                self.output.markTrackLoaded(generation: self.generation)
                try self.refillTo(targetBufferedFrames: self.output.primeFrameCount)
                if wasPlaying {
                    try self.output.start()
                    self.output.restoreAfterTransition()
                    self.outputHeartbeat.reset(expectingRenderRequests: true)
                    self.startRefillTimer()
                } else {
                    stream.setSuspended(true)
                    self.outputHeartbeat.reset(expectingRenderRequests: false)
                }
            } catch {
                self.output.stop()
                self.outputHeartbeat.reset(expectingRenderRequests: false)
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
