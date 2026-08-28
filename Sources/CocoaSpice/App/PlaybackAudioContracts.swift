import Foundation

enum PlaybackOutputHealth: String, Codable, Equatable, Sendable {
    case inactive
    case running
    case stalled
}

struct PlaybackDiagnosticsSnapshot: Codable, Equatable, Sendable {
    let decoderFamily: String?
    let decoderSampleRate: Int
    let decodedFrames: Int64
    let audiblePositionFrames: Int64
    let tempo: Double
    let bufferedFrames: Int64
    let ringBufferFrames: Int64
    let underrunCount: Int64
    let clippedSampleCount: Int64
    let sampleRate: Int
    let outputHealth: PlaybackOutputHealth

    static let idle = PlaybackDiagnosticsSnapshot(
        decoderFamily: nil,
        decoderSampleRate: 0,
        decodedFrames: 0,
        audiblePositionFrames: 0,
        tempo: 1,
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
