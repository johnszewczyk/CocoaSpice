import Foundation

enum PlaybackTransportState: String, Equatable, Sendable {
    case stopped
    case loading
    case paused
    case playing
    case seeking
    case ended
    case failed
}

enum NativeAudioOutputState: String, Equatable, Sendable {
    case unavailable
    case stopped
    case primed
    case running
    case failed
}

struct NativeAudioOutputSnapshot: Equatable, Sendable {
    let transportState: PlaybackTransportState
    let outputState: NativeAudioOutputState
    let trackLoaded: Bool
    let decodeError: String?
    let reachedEnd: Bool
    let sampleRate: Int
    let channelCount: Int
    let bufferedFrames: Int64
    let ringBufferFrames: Int64
    let framesRequested: Int64
    let framesSupplied: Int64
    let underrunCount: Int64
    let clippedSampleCount: Int64
    let positionFrames: Int64
    let generation: Int
}

struct PlaybackDiagnosticsSnapshot: Equatable, Sendable {
    let bufferedFrames: Int64
    let ringBufferFrames: Int64
    let underrunCount: Int64
    let clippedSampleCount: Int64
    let sampleRate: Int

    static let idle = PlaybackDiagnosticsSnapshot(
        bufferedFrames: 0,
        ringBufferFrames: 0,
        underrunCount: 0,
        clippedSampleCount: 0,
        sampleRate: 0
    )

    var bufferedMilliseconds: Int {
        guard sampleRate > 0 else { return 0 }
        return Int((bufferedFrames * 1_000) / Int64(sampleRate))
    }

    var bufferPercent: Int {
        guard ringBufferFrames > 0 else { return 0 }
        return Int((bufferedFrames * 100) / ringBufferFrames)
    }
}

protocol NativeAudioOutput: AnyObject, Sendable {
    var snapshot: NativeAudioOutputSnapshot { get }

    func start() throws
    func pause()
    func finish()
    func prepareForRestart()
    func stop()
    func clear()
}

enum PlaybackFrameAccounting {
    static func positionFrames(
        sessionStartFrame: Int64,
        framesSupplied: Int64
    ) -> Int64 {
        sessionStartFrame + max(0, framesSupplied)
    }

    static func positionSeconds(
        sessionStartFrame: Int64,
        framesSupplied: Int64,
        sampleRate: Int
    ) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(positionFrames(
            sessionStartFrame: sessionStartFrame,
            framesSupplied: framesSupplied
        )) / Double(sampleRate)
    }
}

enum PlaybackCompletionPolicy {
    static func shouldFinish(
        reachedDecoderEnd: Bool,
        plannedFrameCount: Int64?,
        framesSupplied: Int64,
        bufferedFrames: Int64
    ) -> Bool {
        guard bufferedFrames <= 0 else { return false }

        if let plannedFrameCount {
            return framesSupplied >= max(0, plannedFrameCount)
        }

        return reachedDecoderEnd
    }
}
