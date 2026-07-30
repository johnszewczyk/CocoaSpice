import Foundation

/// A small group of Nintendo DS rips are named `.wav` but contain headerless
/// signed 8-bit mono PCM at 22,050 Hz.
/// Keep the recognition deliberately narrow so malformed WAV files are not
/// guessed as raw audio.
enum NDSRawPCM22 {
    static let sampleRate = 22_050
    static func isRecognized(_ fileURL: URL) -> Bool {
        guard fileURL.pathExtension.lowercased() == "wav",
              fileURL.lastPathComponent.range(of: "_[0-9]{2}\\.wav$", options: .regularExpression) != nil,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              data.count >= 64 * 1_024,
              data.prefix(4) != Data("RIFF".utf8),
              data.prefix(4) != Data("SWAV".utf8) else {
            return false
        }
        return true
    }

    static func audioData(from fileURL: URL) throws -> Data {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard isRecognized(fileURL) else {
            throw SPCDecoderError.initializationFailed
        }
        return data
    }
}

final class NDSRawPCM22Decoder: AudioTrackDecoder {
    let sampleRate = NDSRawPCM22.sampleRate
    let appliesFadeInternally = false
    private let samples: Data
    private var framePosition = 0
    private let displayName: String

    init(track: TrackItem, sampleRate: Int) throws {
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        samples = try NDSRawPCM22.audioData(from: fileURL)
        displayName = fileURL.deletingPathExtension().lastPathComponent
    }

    var playedFrames: Int { framePosition }
    var trackEnded: Bool { framePosition >= samples.count }

    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {}

    func seek(toMilliseconds milliseconds: Int) throws {
        let target = max(0, milliseconds) * sampleRate / 1_000
        framePosition = min(target, samples.count)
    }

    func metadata() throws -> TrackMetadata {
        TrackMetadata(
            game: "",
            song: displayName,
            system: "Nintendo DS",
            author: "",
            comment: "Raw PCM 22 kHz",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: samples.count * 1_000 / sampleRate,
            fadeLengthMs: 0
        )
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        let availableFrames = max(0, samples.count - framePosition)
        let frames = min(max(0, frameCount), availableFrames)
        guard frames > 0 else { return DecodedChunk(left: [], right: [], frameCount: 0) }

        var left = [Float](repeating: 0, count: frames)
        for index in 0..<frames {
            let value = Int8(bitPattern: samples[framePosition + index])
            left[index] = Float(value) / Float(Int8.max)
        }
        framePosition += frames
        return DecodedChunk(left: left, right: left, frameCount: frames)
    }
}

final class NDSRawPCM22FileInspector: AudioFileInspector {
    let trackCount = 1
    private let metadataValue: TrackMetadata

    init(fileURL: URL) throws {
        let samples = try NDSRawPCM22.audioData(from: fileURL)
        metadataValue = TrackMetadata(
            game: "",
            song: fileURL.deletingPathExtension().lastPathComponent,
            system: "Nintendo DS",
            author: "",
            comment: "Raw PCM 22 kHz",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: samples.count * 1_000 / NDSRawPCM22.sampleRate,
            fadeLengthMs: 0
        )
    }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard trackIndex == 0 else { throw SPCDecoderError.initializationFailed }
        return metadataValue
    }
}
