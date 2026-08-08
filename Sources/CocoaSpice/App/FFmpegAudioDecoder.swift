import Foundation
import CFFmpegAudio

/// Finite audio containers not accepted by AVAudioFile. FFmpeg is kept behind
/// the same streaming contract as every other native decoder, so decoding
/// never occurs from Core Audio's realtime callback.
final class FFmpegAudioDecoder: AudioTrackDecoder {
    let sampleRate: Int
    let appliesFadeInternally = false
    private var handle: UnsafeMutableRawPointer?
    private let fileURL: URL

    init(track: TrackItem, sampleRate: Int) throws {
        fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        let opened = fileURL.path.withCString { cocoaspice_ffmpeg_audio_open($0, Int32(sampleRate)) }
        guard let opened else { throw SPCDecoderError.initializationFailed }
        handle = opened
        self.sampleRate = max(1, Int(cocoaspice_ffmpeg_audio_sample_rate(opened)))
    }

    deinit {
        if let handle { cocoaspice_ffmpeg_audio_close(handle) }
    }

    var playedFrames: Int { handle.map { max(0, Int(cocoaspice_ffmpeg_audio_played_frames($0))) } ?? 0 }
    var trackEnded: Bool { handle.map { cocoaspice_ffmpeg_audio_finished($0) != 0 } ?? true }
    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {}

    func seek(toMilliseconds milliseconds: Int) throws {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        cocoaspice_ffmpeg_audio_seek(handle, Int64(max(0, milliseconds)) * Int64(sampleRate) / 1_000)
    }

    func metadata() throws -> TrackMetadata {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        return Self.metadata(fileURL: fileURL, handle: handle, sampleRate: sampleRate)
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var samples = [Int16](repeating: 0, count: max(1, frameCount) * 2)
        let rendered = Int(cocoaspice_ffmpeg_audio_read(handle, &samples, Int32(frameCount)))
        guard rendered >= 0 else { throw SPCDecoderError.initializationFailed }
        var left = [Float](repeating: 0, count: rendered)
        var right = [Float](repeating: 0, count: rendered)
        for frame in 0..<rendered {
            left[frame] = PCMFloatConversion.normalized(samples[frame * 2])
            right[frame] = PCMFloatConversion.normalized(samples[frame * 2 + 1])
        }
        return DecodedChunk(left: left, right: right, frameCount: rendered)
    }

    fileprivate static func metadata(fileURL: URL, handle: UnsafeMutableRawPointer, sampleRate: Int) -> TrackMetadata {
        let title = string(cocoaspice_ffmpeg_audio_title(handle))
        let frames = cocoaspice_ffmpeg_audio_length_frames(handle)
        return TrackMetadata(
            game: "", song: title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : title,
            system: "Sega Saturn", author: "", comment: string(cocoaspice_ffmpeg_audio_format_name(handle)),
            introLengthMs: 0, loopLengthMs: 0,
            playLengthMs: max(0, Int(frames * 1_000 / Int64(max(1, sampleRate)))), fadeLengthMs: 0
        )
    }

    fileprivate static func string(_ pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }
}

final class FFmpegAudioFileInspector: AudioFileInspector {
    let trackCount = 1
    private let trackMetadata: TrackMetadata

    init(fileURL: URL) throws {
        let handle = fileURL.path.withCString { cocoaspice_ffmpeg_audio_open($0, 44_100) }
        guard let handle else { throw SPCDecoderError.initializationFailed }
        defer { cocoaspice_ffmpeg_audio_close(handle) }
        trackMetadata = FFmpegAudioDecoder.metadata(
            fileURL: fileURL,
            handle: handle,
            sampleRate: max(1, Int(cocoaspice_ffmpeg_audio_sample_rate(handle)))
        )
    }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard trackIndex == 0 else { throw SPCDecoderError.library("FFmpeg audio files expose one playable track.") }
        return trackMetadata
    }
}
