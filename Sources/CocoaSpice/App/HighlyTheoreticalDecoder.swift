import Foundation
import CHighlyTheoretical

/// Sega Saturn SSF/miniSSF playback through Highly Theoretical's SCSP core.
final class HighlyTheoreticalDecoder: AudioTrackDecoder {
    let sampleRate = 44_100
    let appliesFadeInternally = false
    private var handle: UnsafeMutableRawPointer?
    private let fileURL: URL

    init(track: TrackItem, sampleRate: Int) throws {
        fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        var errorMessage: UnsafeMutablePointer<CChar>?
        handle = fileURL.path.withCString { highly_theoretical_player_create($0, &errorMessage) }
        defer { if let errorMessage { highly_theoretical_error_message_free(errorMessage) } }
        guard handle != nil else {
            throw SPCDecoderError.library(errorMessage.map { String(cString: $0) } ?? "Could not initialize Sega Saturn playback.")
        }
    }

    deinit { if let handle { highly_theoretical_player_destroy(handle) } }

    var playedFrames: Int { handle.map { Int(highly_theoretical_player_played_frames($0)) } ?? 0 }
    var trackEnded: Bool { false }

    func metadata() throws -> TrackMetadata {
        guard let metadata = try PSFMetadataReader.read(fileURL: fileURL) else {
            throw SPCDecoderError.library("Could not read SSF metadata.")
        }
        return metadata
    }

    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {}

    func seek(toMilliseconds milliseconds: Int) throws {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = highly_theoretical_player_seek_milliseconds(handle, Int32(milliseconds), &errorMessage)
        defer { if let errorMessage { highly_theoretical_error_message_free(errorMessage) } }
        guard result == 0 else {
            throw SPCDecoderError.library(errorMessage.map { String(cString: $0) } ?? "SSF seeking failed.")
        }
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var samples = [Int16](repeating: 0, count: frameCount * 2)
        var renderedFrames: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = highly_theoretical_player_render_s16(handle, Int32(frameCount), &samples, &renderedFrames, &errorMessage)
        defer { if let errorMessage { highly_theoretical_error_message_free(errorMessage) } }
        guard result == 0 else {
            throw SPCDecoderError.library(errorMessage.map { String(cString: $0) } ?? "SSF decoding failed.")
        }
        let rendered = Int(renderedFrames)
        var left = [Float](repeating: 0, count: rendered)
        var right = [Float](repeating: 0, count: rendered)
        for frame in 0..<rendered {
            left[frame] = PCMFloatConversion.normalized(samples[frame * 2])
            right[frame] = PCMFloatConversion.normalized(samples[frame * 2 + 1])
        }
        return DecodedChunk(left: left, right: right, frameCount: rendered)
    }
}

final class HighlyTheoreticalFileInspector: AudioFileInspector {
    let trackCount = 1
    private let fileURL: URL

    init(fileURL: URL) throws { self.fileURL = fileURL }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard let metadata = try PSFMetadataReader.read(fileURL: fileURL) else {
            throw SPCDecoderError.library("Could not read SSF metadata.")
        }
        return metadata
    }
}
