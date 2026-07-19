import Foundation
import CPSF2

final class PSF2Decoder: AudioTrackDecoder {
    let sampleRate = 44_100
    let appliesFadeInternally = false
    private var handle: UnsafeMutableRawPointer?

    init(track: TrackItem, sampleRate: Int) throws {
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        handle = fileURL.path.withCString { cocoaspice_psf2_open($0) }
        guard handle != nil else { throw SPCDecoderError.initializationFailed }
    }

    deinit { if let handle { cocoaspice_psf2_close(handle) } }

    var playedFrames: Int { handle.map { Int(cocoaspice_psf2_played_frames($0)) } ?? 0 }
    var trackEnded: Bool { handle.map { cocoaspice_psf2_finished($0) != 0 } ?? true }
    func setLongPlayEnabled(_ enabled: Bool) {
        if let handle { cocoaspice_psf2_set_long_play(handle, enabled ? 1 : 0) }
    }
    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {}
    func setSuspended(_ suspended: Bool) {
        if let handle {
            cocoaspice_psf2_set_suspended(handle, suspended ? 1 : 0)
        }
    }

    func seek(toMilliseconds milliseconds: Int) throws {
        guard let handle, cocoaspice_psf2_seek(handle, Int64(milliseconds) * 44_100 / 1_000) == 0 else {
            throw SPCDecoderError.initializationFailed
        }
    }

    func metadata() throws -> TrackMetadata {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        let length = Int(cocoaspice_psf2_play_length_frames(handle) * 1_000 / 44_100)
        return TrackMetadata(
            game: tag(handle, "game"), song: tag(handle, "title"), system: "PlayStation 2",
            author: tag(handle, "artist"), comment: tag(handle, "comment"),
            introLengthMs: 0, loopLengthMs: 0, playLengthMs: length,
            fadeLengthMs: 0
        )
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var samples = [Int16](repeating: 0, count: frameCount * 2)
        let rendered = Int(cocoaspice_psf2_read(handle, &samples, Int32(frameCount)))
        guard rendered >= 0 else { throw SPCDecoderError.initializationFailed }
        var left = [Float](repeating: 0, count: rendered)
        var right = [Float](repeating: 0, count: rendered)
        for frame in 0..<rendered {
            left[frame] = Float(samples[frame * 2]) / Float(Int16.max)
            right[frame] = Float(samples[frame * 2 + 1]) / Float(Int16.max)
        }
        return DecodedChunk(left: left, right: right, frameCount: rendered)
    }

    private func tag(_ handle: UnsafeMutableRawPointer, _ name: String) -> String {
        name.withCString { pointer in
            guard let value = cocoaspice_psf2_tag(handle, pointer) else { return "" }
            return String(cString: value)
        }
    }
}

final class PSF2FileInspector: AudioFileInspector {
    let trackCount = 1
    private var handle: UnsafeMutableRawPointer?
    init(fileURL: URL) throws {
        handle = fileURL.path.withCString { cocoaspice_psf2_metadata_open($0) }
        guard handle != nil else { throw SPCDecoderError.initializationFailed }
    }

    deinit { if let handle { cocoaspice_psf2_metadata_close(handle) } }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        let length = Int(cocoaspice_psf2_metadata_play_length_frames(handle) * 1_000 / 44_100)
        return TrackMetadata(
            game: tag(handle, "game"), song: tag(handle, "title"), system: "PlayStation 2",
            author: tag(handle, "artist"), comment: tag(handle, "comment"),
            introLengthMs: 0, loopLengthMs: 0, playLengthMs: length,
            fadeLengthMs: 0
        )
    }

    private func tag(_ handle: UnsafeMutableRawPointer, _ name: String) -> String {
        name.withCString { pointer in
            guard let value = cocoaspice_psf2_metadata_tag(handle, pointer) else { return "" }
            return String(cString: value)
        }
    }
}
