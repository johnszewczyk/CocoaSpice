import Foundation

enum PCMFloatConversion {
    /// Canonical signed 16-bit PCM normalization: -32,768 maps exactly to
    /// -1.0 while +32,767 remains just below +1.0. Dividing by Int16.max
    /// misclassifies every legal minimum sample as an over-range clip.
    static func normalized(_ sample: Int16) -> Float {
        Float(sample) / 32_768
    }
}

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

enum PlaybackOutputHealth: String, Equatable, Sendable {
    case inactive
    case running
    case stalled
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
    let engineIsRunning: Bool
}

struct PlaybackDiagnosticsSnapshot: Equatable, Sendable {
    let bufferedFrames: Int64
    let ringBufferFrames: Int64
    let underrunCount: Int64
    let clippedSampleCount: Int64
    let sampleRate: Int
    let outputHealth: PlaybackOutputHealth

    static let idle = PlaybackDiagnosticsSnapshot(
        bufferedFrames: 0,
        ringBufferFrames: 0,
        underrunCount: 0,
        clippedSampleCount: 0,
        sampleRate: 0,
        outputHealth: .inactive
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

/// Tracks whether the system output is still pulling PCM without ever touching
/// a decoder or the realtime render callback. The lock is only used by the UI
/// diagnostics path and session control operations; the callback writes its
/// counters to the atomic C ring buffer instead.
final class PlaybackOutputHeartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var expectingRenderRequests = false
    private var lastRequestCount: Int64 = 0
    private var lastProgressDate = Date.distantPast

    func reset(expectingRenderRequests: Bool, now: Date = Date()) {
        lock.lock()
        self.expectingRenderRequests = expectingRenderRequests
        lastRequestCount = 0
        lastProgressDate = now
        lock.unlock()
    }

    func health(framesRequested: Int64, now: Date = Date()) -> PlaybackOutputHealth {
        lock.lock()
        defer { lock.unlock() }

        guard expectingRenderRequests else { return .inactive }
        if framesRequested > lastRequestCount {
            lastRequestCount = framesRequested
            lastProgressDate = now
            return .running
        }
        return now.timeIntervalSince(lastProgressDate) >= 2 ? .stalled : .running
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
