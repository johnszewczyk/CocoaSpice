import Foundation
import C2SF

final class TwoSFDecoder: AudioTrackDecoder {
    let sampleRate: Int
    let appliesFadeInternally = true
    private var handle: twosf_player_handle_t?

    init(track: TrackItem, sampleRate: Int) throws {
        self.sampleRate = sampleRate
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let createdHandle = TwoSFBridgeGate.withLock {
            fileURL.path.withCString { twosf_player_create($0, Int32(sampleRate), &errorMessage) }
        }
        guard let createdHandle else {
            defer { Self.freeErrorMessage(errorMessage) }
            if let errorMessage { throw SPCDecoderError.library(String(cString: errorMessage)) }
            throw SPCDecoderError.initializationFailed
        }
        handle = createdHandle
    }

    deinit {
        if let handle { TwoSFBridgeGate.withLock { twosf_player_destroy(handle) } }
    }

    func metadata() throws -> TrackMetadata {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var raw = twosf_metadata_t()
        defer { twosf_metadata_clear(&raw) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = TwoSFBridgeGate.withLock { twosf_player_read_metadata(handle, &raw, &errorMessage) }
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
        return Self.trackMetadata(from: raw)
    }

    var playedFrames: Int {
        guard let handle else { return 0 }
        return TwoSFBridgeGate.withLock { Int(twosf_player_played_frames(handle)) }
    }

    var trackEnded: Bool {
        guard let handle else { return true }
        return TwoSFBridgeGate.withLock { twosf_player_track_ended(handle) != 0 }
    }

    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {
        guard let handle, !usesNativeEnding else { return }
        var errorMessage: UnsafeMutablePointer<CChar>?
        TwoSFBridgeGate.withLock {
            _ = twosf_player_configure(handle, Int32(loopSeconds * 1_000), Int32(fadeSeconds * 1_000), &errorMessage)
        }
        Self.freeErrorMessage(errorMessage)
    }

    func seek(toMilliseconds milliseconds: Int) throws {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = TwoSFBridgeGate.withLock { twosf_player_seek_milliseconds(handle, Int32(milliseconds), &errorMessage) }
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var interleaved = [Int16](repeating: 0, count: frameCount * 2)
        var rendered: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = TwoSFBridgeGate.withLock {
            twosf_player_render_s16(handle, Int32(frameCount), &interleaved, &rendered, &errorMessage)
        }
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
        let count = max(0, Int(rendered))
        var left = [Float](repeating: 0, count: count)
        var right = [Float](repeating: 0, count: count)
        for frame in 0..<count {
            left[frame] = PCMFloatConversion.normalized(interleaved[frame * 2])
            right[frame] = PCMFloatConversion.normalized(interleaved[frame * 2 + 1])
        }
        return DecodedChunk(left: left, right: right, frameCount: count)
    }

    static func trackMetadata(from raw: twosf_metadata_t) -> TrackMetadata {
        TrackMetadata(
            game: string(from: raw.game), song: string(from: raw.title), system: string(from: raw.system),
            author: string(from: raw.artist), comment: string(from: raw.comment), introLengthMs: 0,
            loopLengthMs: 0, playLengthMs: Int(raw.play_length_ms), fadeLengthMs: Int(raw.fade_length_ms)
        )
    }

    static func throwIfNeeded(_ status: Int32, errorMessage: UnsafeMutablePointer<CChar>?) throws {
        defer { freeErrorMessage(errorMessage) }
        guard status == 0 else {
            if let errorMessage { throw SPCDecoderError.library(String(cString: errorMessage)) }
            throw SPCDecoderError.initializationFailed
        }
    }

    private static func string(from pointer: UnsafeMutablePointer<CChar>?) -> String {
        pointer.map { String(cString: $0) } ?? ""
    }

    private static func freeErrorMessage(_ errorMessage: UnsafeMutablePointer<CChar>?) {
        if let errorMessage { twosf_error_message_free(errorMessage) }
    }
}

final class TwoSFFileInspector: AudioFileInspector {
    let trackCount = 1
    private let trackMetadata: TrackMetadata

    init(fileURL: URL) throws {
        var raw = twosf_metadata_t()
        defer { twosf_metadata_clear(&raw) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = TwoSFBridgeGate.withLock {
            fileURL.path.withCString { twosf_inspect_metadata($0, &raw, &errorMessage) }
        }
        try TwoSFDecoder.throwIfNeeded(status, errorMessage: errorMessage)
        trackMetadata = TwoSFDecoder.trackMetadata(from: raw)
    }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard trackIndex == 0 else { throw SPCDecoderError.library("2SF files expose a single playable track.") }
        return trackMetadata
    }
}
