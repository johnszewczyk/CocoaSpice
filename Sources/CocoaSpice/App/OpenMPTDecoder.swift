import Foundation
import COpenMPT

final class OpenMPTDecoder: AudioTrackDecoder {
    let sampleRate: Int
    let appliesFadeInternally = false
    private var handle: openmpt_player_handle_t?

    init(track: TrackItem, sampleRate: Int) throws {
        self.sampleRate = sampleRate
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let created = fileURL.path.withCString { openmpt_player_create($0, Int32(sampleRate), &errorMessage) }
        guard let created else {
            defer { Self.freeErrorMessage(errorMessage) }
            if let errorMessage { throw SPCDecoderError.library(String(cString: errorMessage)) }
            throw SPCDecoderError.initializationFailed
        }
        handle = created
    }

    deinit {
        if let handle { openmpt_player_destroy(handle) }
    }

    func metadata() throws -> TrackMetadata {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var raw = openmpt_metadata_t()
        defer { openmpt_metadata_clear(&raw) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = openmpt_player_read_metadata(handle, &raw, &errorMessage)
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
        return Self.trackMetadata(from: raw)
    }

    var playedFrames: Int { handle.map { Int(openmpt_player_played_frames($0)) } ?? 0 }
    var trackEnded: Bool { handle.map { openmpt_player_track_ended($0) != 0 } ?? true }

    func setLongPlayEnabled(_ enabled: Bool) {
        guard let handle else { return }
        var errorMessage: UnsafeMutablePointer<CChar>?
        _ = openmpt_player_set_long_play(handle, enabled ? 1 : 0, &errorMessage)
        Self.freeErrorMessage(errorMessage)
    }

    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {}

    func seek(toMilliseconds milliseconds: Int) throws {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = openmpt_player_seek_milliseconds(handle, Int32(milliseconds), &errorMessage)
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var interleaved = [Int16](repeating: 0, count: frameCount * 2)
        var rendered: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = openmpt_player_render_s16(handle, Int32(frameCount), &interleaved, &rendered, &errorMessage)
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
        let count = max(0, Int(rendered))
        var left = [Float](repeating: 0, count: count)
        var right = [Float](repeating: 0, count: count)
        for frame in 0..<count {
            left[frame] = Float(interleaved[frame * 2]) / Float(Int16.max)
            right[frame] = Float(interleaved[frame * 2 + 1]) / Float(Int16.max)
        }
        return DecodedChunk(left: left, right: right, frameCount: count)
    }

    static func trackMetadata(from raw: openmpt_metadata_t) -> TrackMetadata {
        TrackMetadata(
            game: "", song: string(from: raw.title), system: "Tracker Module",
            author: string(from: raw.artist), comment: string(from: raw.tracker), introLengthMs: 0,
            loopLengthMs: 0, playLengthMs: Int(raw.play_length_ms), fadeLengthMs: 0
        )
    }

    static func throwIfNeeded(_ status: Int32, errorMessage: UnsafeMutablePointer<CChar>?) throws {
        defer { freeErrorMessage(errorMessage) }
        guard status == 0 else {
            if let errorMessage { throw SPCDecoderError.library(String(cString: errorMessage)) }
            throw SPCDecoderError.initializationFailed
        }
    }

    private static func string(from value: UnsafeMutablePointer<CChar>?) -> String {
        value.map { String(cString: $0) } ?? ""
    }

    private static func freeErrorMessage(_ errorMessage: UnsafeMutablePointer<CChar>?) {
        if let errorMessage { openmpt_error_message_free(errorMessage) }
    }
}

final class OpenMPTFileInspector: AudioFileInspector {
    let trackCount = 1
    private let trackMetadata: TrackMetadata

    init(fileURL: URL) throws {
        var raw = openmpt_metadata_t()
        defer { openmpt_metadata_clear(&raw) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = fileURL.path.withCString { openmpt_inspect_file($0, &raw, &errorMessage) }
        try OpenMPTDecoder.throwIfNeeded(status, errorMessage: errorMessage)
        trackMetadata = OpenMPTDecoder.trackMetadata(from: raw)
    }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard trackIndex == 0 else { throw SPCDecoderError.library("Tracker modules expose a single playable track.") }
        return trackMetadata
    }
}
