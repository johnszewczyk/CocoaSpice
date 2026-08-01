import Foundation
import CVGMStream

final class VGMStreamDecoder: AudioTrackDecoder {
    let sampleRate: Int
    let appliesFadeInternally = false
    private var handle: UnsafeMutableRawPointer?
    private var compatibilityAliasURL: URL?
    private let channels: Int
    private let systemName: String

    init(track: TrackItem, sampleRate: Int) throws {
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        let playableURL = try Self.compatibleURL(for: fileURL)
        let subsong = track.trackIndex == 0 ? 0 : track.trackIndex + 1
        let opened = playableURL.path.withCString { path in
            cocoaspice_vgmstream_open(path, Int32(subsong), Int32(sampleRate))
        }
        guard let opened else {
            throw SPCDecoderError.initializationFailed
        }
        handle = opened
        channels = max(1, Int(cocoaspice_vgmstream_channels(opened)))
        self.sampleRate = max(1, Int(cocoaspice_vgmstream_sample_rate(opened)))
        systemName = Self.systemName(forPathExtension: fileURL.pathExtension)
        compatibilityAliasURL = playableURL == fileURL ? nil : playableURL
    }

    deinit {
        if let handle { cocoaspice_vgmstream_close(handle) }
        if let compatibilityAliasURL { try? FileManager.default.removeItem(at: compatibilityAliasURL) }
    }

    static func isNintendoDSSWAV(_ fileURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]), data.count >= 4 else { return false }
        return data.prefix(4) == Data("SWAV".utf8)
    }

    fileprivate static func compatibleURL(for fileURL: URL) throws -> URL {
        if isNintendoDSSWAV(fileURL), fileURL.pathExtension.lowercased() == "wav" {
            let aliasURL = fileURL.deletingPathExtension().appendingPathExtension("adpcm")
            if !FileManager.default.fileExists(atPath: aliasURL.path) {
                try FileManager.default.linkItem(at: fileURL, to: aliasURL)
            }
            return aliasURL
        }
        return fileURL
    }
    var playedFrames: Int {
        guard let handle else { return 0 }
        return max(0, Int(cocoaspice_vgmstream_played_frames(handle)))
    }
    var trackEnded: Bool { guard let handle else { return true }; return cocoaspice_vgmstream_finished(handle) != 0 }
    func setLongPlayEnabled(_ enabled: Bool) {
        guard let handle else { return }
        _ = cocoaspice_vgmstream_set_long_play(handle, enabled ? 1 : 0)
    }
    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {}
    func seek(toMilliseconds milliseconds: Int) throws {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        let frame = max(0, Int64(milliseconds) * Int64(sampleRate) / 1_000)
        cocoaspice_vgmstream_seek(handle, frame)
    }

    func metadata() throws -> TrackMetadata {
        let playLength = handle.map { Int(cocoaspice_vgmstream_play_length_frames($0) * 1_000 / Int64(sampleRate)) } ?? 0
        let loopLength = handle.map { Int(cocoaspice_vgmstream_loop_length_frames($0) * 1_000 / Int64(sampleRate)) } ?? 0
        return TrackMetadata(game: "", song: string(cocoaspice_vgmstream_stream_name(handle)), system: systemName, author: "", comment: string(cocoaspice_vgmstream_format_name(handle)), introLengthMs: 0, loopLengthMs: loopLength, playLengthMs: playLength, fadeLengthMs: 0)
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var samples = [Int16](repeating: 0, count: frameCount * channels)
        let renderedRaw = cocoaspice_vgmstream_read(handle, &samples, Int32(frameCount))
        guard renderedRaw >= 0 else {
            throw SPCDecoderError.initializationFailed
        }
        let rendered = Int(renderedRaw)
        var left = [Float](repeating: 0, count: rendered)
        var right = [Float](repeating: 0, count: rendered)
        for frame in 0..<rendered {
            left[frame] = PCMFloatConversion.normalized(samples[frame * channels])
            right[frame] = channels > 1 ? PCMFloatConversion.normalized(samples[frame * channels + 1]) : left[frame]
        }
        return DecodedChunk(left: left, right: right, frameCount: rendered)
    }

    private func string(_ pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }

    fileprivate static func systemName(forPathExtension extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "wav": "Nintendo DS"
        case "xa": "PlayStation"
        case "aifc", "genh", "stream": "3DO"
        case "aa3", "at3": "PlayStation 3 / PSP"
        case "bnk": "Game Audio"
        case "msf": "PlayStation 3"
        case "ogg", "rws": "Game Audio"
        default: "PlayStation 2"
        }
    }
}

final class VGMStreamFileInspector: AudioFileInspector {
    let trackCount: Int
    private let fileURL: URL
    init(fileURL: URL) throws {
        let playableURL = try VGMStreamDecoder.compatibleURL(for: fileURL)
        self.fileURL = playableURL
        let opened = playableURL.path.withCString { path in cocoaspice_vgmstream_open(path, 0, 44_100) }
        guard let opened else { throw SPCDecoderError.initializationFailed }
        trackCount = max(1, Int(cocoaspice_vgmstream_subsong_count(opened)))
        cocoaspice_vgmstream_close(opened)
    }
    func metadata(trackIndex: Int) throws -> TrackMetadata {
        let opened = fileURL.path.withCString { path in cocoaspice_vgmstream_open(path, Int32(trackIndex + 1), 44_100) }
        guard let opened else { throw SPCDecoderError.initializationFailed }
        defer { cocoaspice_vgmstream_close(opened) }
        let rate = max(1, Int(cocoaspice_vgmstream_sample_rate(opened)))
        return TrackMetadata(game: "", song: string(cocoaspice_vgmstream_stream_name(opened)), system: VGMStreamDecoder.systemName(forPathExtension: fileURL.pathExtension), author: "", comment: string(cocoaspice_vgmstream_format_name(opened)), introLengthMs: 0, loopLengthMs: Int(cocoaspice_vgmstream_loop_length_frames(opened) * 1_000 / Int64(rate)), playLengthMs: Int(cocoaspice_vgmstream_play_length_frames(opened) * 1_000 / Int64(rate)), fadeLengthMs: 0)
    }

    private func string(_ pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }
}
