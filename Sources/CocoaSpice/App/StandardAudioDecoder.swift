import AVFoundation

/// Core Audio owns ordinary, self-contained PCM and FLAC files. Keep it behind
/// the app's decoder contract so library scanning and playback use one route.
final class StandardAudioDecoder: AudioTrackDecoder {
    let sampleRate: Int
    let appliesFadeInternally = false

    private let audioFile: AVAudioFile
    private let format: AVAudioFormat
    private let systemName: String
    private let formatName: String

    init(track: TrackItem, sampleRate: Int) throws {
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        audioFile = try AVAudioFile(
            forReading: fileURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        format = audioFile.processingFormat
        self.sampleRate = max(1, Int(format.sampleRate.rounded()))
        systemName = "Standard Audio"
        formatName = Self.formatName(for: fileURL.pathExtension)
    }

    var playedFrames: Int {
        max(0, Int(audioFile.framePosition))
    }

    var trackEnded: Bool {
        audioFile.framePosition >= audioFile.length
    }

    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {}

    func seek(toMilliseconds milliseconds: Int) throws {
        let frame = AVAudioFramePosition(
            max(0, Int64(milliseconds) * Int64(sampleRate) / 1_000)
        )
        audioFile.framePosition = min(frame, audioFile.length)
    }

    func metadata() throws -> TrackMetadata {
        Self.metadata(
            fileURL: audioFile.url,
            sampleRate: sampleRate,
            frameCount: audioFile.length,
            systemName: systemName,
            formatName: formatName
        )
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        // AVAudioFile can throw its unhelpful `nilError` when it is asked to
        // read after the final frame. EOF is a normal transport event: return
        // an empty chunk so PlaybackStreamSession marks reachedEnd and the
        // playlist can advance or repeat the current item.
        guard !trackEnded else {
            return DecodedChunk(left: [], right: [], frameCount: 0)
        }

        let capacity = AVAudioFrameCount(max(1, frameCount))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw SPCDecoderError.initializationFailed
        }
        try audioFile.read(into: buffer, frameCount: capacity)

        let frames = Int(buffer.frameLength)
        guard frames > 0 else {
            return DecodedChunk(left: [], right: [], frameCount: 0)
        }
        guard let channels = buffer.floatChannelData else {
            throw SPCDecoderError.initializationFailed
        }

        let channelCount = max(1, Int(format.channelCount))
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            left[frame] = channels[0][frame]
            right[frame] = channelCount > 1 ? channels[1][frame] : left[frame]
        }
        return DecodedChunk(left: left, right: right, frameCount: frames)
    }

    static func metadata(
        fileURL: URL,
        sampleRate: Int,
        frameCount: AVAudioFramePosition,
        systemName: String,
        formatName: String
    ) -> TrackMetadata {
        TrackMetadata(
            game: "",
            song: fileURL.deletingPathExtension().lastPathComponent,
            system: systemName,
            author: "",
            comment: formatName,
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: max(0, Int(frameCount * 1_000 / AVAudioFramePosition(max(1, sampleRate)))),
            fadeLengthMs: 0
        )
    }

    static func formatName(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "flac": "FLAC"
        case "wav": "WAV"
        default: extensionName.uppercased()
        }
    }
}

final class StandardAudioFileInspector: AudioFileInspector {
    let trackCount = 1
    private let trackMetadata: TrackMetadata

    init(fileURL: URL) throws {
        let audioFile = try AVAudioFile(
            forReading: fileURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let sampleRate = max(1, Int(audioFile.processingFormat.sampleRate.rounded()))
        trackMetadata = StandardAudioDecoder.metadata(
            fileURL: fileURL,
            sampleRate: sampleRate,
            frameCount: audioFile.length,
            systemName: "Standard Audio",
            formatName: StandardAudioDecoder.formatName(for: fileURL.pathExtension)
        )
    }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard trackIndex == 0 else {
            throw SPCDecoderError.library("Standard audio files expose a single playable track.")
        }
        return trackMetadata
    }
}
