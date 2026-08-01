import Foundation
import COpenMPT
import CLibVGM
import CHighlyComplete
import CHighlyTheoretical
import CLazyUSF
import C2SF
import CVGMStream
import CPlayPSF

private enum HighlyCompleteBridgeGate {
    private static let lock = NSLock()

    static func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

enum TwoSFBridgeGate {
    private static let lock = NSLock()

    static func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

protocol AudioTrackDecoder {
    var sampleRate: Int { get }
    var playedFrames: Int { get }
    var trackEnded: Bool { get }
    var appliesFadeInternally: Bool { get }

    func metadata() throws -> TrackMetadata
    func setLongPlayEnabled(_ enabled: Bool)
    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool)
    func setSuspended(_ suspended: Bool)
    func seek(toMilliseconds milliseconds: Int) throws
    func decode(frameCount: Int) throws -> DecodedChunk
}

extension AudioTrackDecoder {
    func setLongPlayEnabled(_ enabled: Bool) {}
    func setSuspended(_ suspended: Bool) {}
}

protocol AudioFileInspector {
    var trackCount: Int { get }
    func metadata(trackIndex: Int) throws -> TrackMetadata
}

enum PlaybackDecoderFactory {
    static func makeDecoder(track: TrackItem, sampleRate: Int) throws -> any AudioTrackDecoder {
        if track.playablePathExtension.lowercased() == "wav",
           let fileURL = try? ZipArchiveSupport.materializePlayableFile(for: track),
           VGMStreamDecoder.isNintendoDSSWAV(fileURL) {
            return try VGMStreamDecoder(track: track, sampleRate: sampleRate)
        }
        if track.playablePathExtension.lowercased() == "wav",
           let fileURL = try? ZipArchiveSupport.materializePlayableFile(for: track),
           NDSRawPCM22.isRecognized(fileURL) {
            return try NDSRawPCM22Decoder(track: track, sampleRate: sampleRate)
        }
        switch try backend(forPathExtension: track.playablePathExtension) {
        case .gme:
            return try SPCDecoder(track: track, sampleRate: sampleRate)
        case .openMPT:
            return try OpenMPTDecoder(track: track, sampleRate: sampleRate)
        case .standardAudio:
            return try StandardAudioDecoder(track: track, sampleRate: sampleRate)
        case .libvgm:
            return try LibVGMDecoder(track: track, sampleRate: sampleRate)
        case .highlyComplete:
            return try HighlyCompleteDecoder(track: track, sampleRate: sampleRate)
        case .highlyTheoretical:
            return try HighlyTheoreticalDecoder(track: track, sampleRate: sampleRate)
        case .lazyUSF:
            return try LazyUSFDecoder(track: track, sampleRate: sampleRate)
        case .twoSF:
            return try TwoSFDecoder(track: track, sampleRate: sampleRate)
        case .vgmstream:
            return try VGMStreamDecoder(track: track, sampleRate: sampleRate)
        case .playPSF:
            return try PlayPSFDecoder(track: track, sampleRate: sampleRate)
        }
    }

    static func makeInspector(fileURL: URL) throws -> any AudioFileInspector {
        if fileURL.pathExtension.lowercased() == "wav",
           VGMStreamDecoder.isNintendoDSSWAV(fileURL) {
            return try VGMStreamFileInspector(fileURL: fileURL)
        }
        if fileURL.pathExtension.lowercased() == "wav",
           NDSRawPCM22.isRecognized(fileURL) {
            return try NDSRawPCM22FileInspector(fileURL: fileURL)
        }
        switch try backend(forPathExtension: fileURL.pathExtension.lowercased()) {
        case .gme:
            return try SPCFileInspector(fileURL: fileURL)
        case .openMPT:
            return try OpenMPTFileInspector(fileURL: fileURL)
        case .standardAudio:
            return try StandardAudioFileInspector(fileURL: fileURL)
        case .libvgm:
            return try LibVGMFileInspector(fileURL: fileURL)
        case .highlyComplete:
            return try HighlyCompleteFileInspector(fileURL: fileURL)
        case .highlyTheoretical:
            return try HighlyTheoreticalFileInspector(fileURL: fileURL)
        case .lazyUSF:
            return try LazyUSFFileInspector(fileURL: fileURL)
        case .twoSF:
            return try TwoSFFileInspector(fileURL: fileURL)
        case .vgmstream:
            return try VGMStreamFileInspector(fileURL: fileURL)
        case .playPSF:
            return try PlayPSFFileInspector(fileURL: fileURL)
        }
    }

    private static func backend(forPathExtension extensionName: String) throws -> PlaybackDecoderBackend {
        guard let backend = PlaybackFormatRegistry.playbackBackend(forPathExtension: extensionName) else {
            throw SPCDecoderError.library("Unsupported audio file type: \(extensionName)")
        }
        return backend
    }
}

extension SPCDecoder: AudioTrackDecoder {
    var appliesFadeInternally: Bool { true }
}

extension SPCFileInspector: AudioFileInspector {}

final class LibVGMDecoder: AudioTrackDecoder {
    let sampleRate: Int
    let appliesFadeInternally = false

    private var handle: UnsafeMutableRawPointer?

    init(track: TrackItem, sampleRate: Int) throws {
        self.sampleRate = sampleRate
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)

        var errorMessage: UnsafeMutablePointer<CChar>?
        let createdHandle = fileURL.path.withCString { path in
            libvgm_player_create(path, Int32(sampleRate), Int32(track.trackIndex), &errorMessage)
        }
        guard let createdHandle else {
            defer { Self.freeErrorMessage(errorMessage) }
            if let errorMessage {
                throw SPCDecoderError.library(String(cString: errorMessage))
            }
            throw SPCDecoderError.initializationFailed
        }

        handle = createdHandle
    }

    deinit {
        if let handle {
            libvgm_player_destroy(handle)
        }
    }

    func metadata() throws -> TrackMetadata {
        guard let handle else {
            throw SPCDecoderError.initializationFailed
        }

        var rawMetadata = libvgm_metadata_t()
        defer { libvgm_metadata_clear(&rawMetadata) }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = libvgm_player_read_metadata(handle, &rawMetadata, &errorMessage)
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
        return Self.trackMetadata(from: rawMetadata)
    }

    var playedFrames: Int {
        guard let handle else {
            return 0
        }
        return Int(libvgm_player_played_frames(handle))
    }

    var trackEnded: Bool {
        guard let handle else { return true }
        return libvgm_player_track_ended(handle) != 0
    }

    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {
        guard let handle else { return }

        var errorMessage: UnsafeMutablePointer<CChar>?
        _ = libvgm_player_configure(
            handle,
            Int32(loopSeconds),
            Int32(fadeSeconds),
            usesNativeEnding,
            &errorMessage
        )
        Self.freeErrorMessage(errorMessage)
    }

    func seek(toMilliseconds milliseconds: Int) throws {
        guard let handle else {
            throw SPCDecoderError.initializationFailed
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = libvgm_player_seek_milliseconds(handle, Int32(milliseconds), &errorMessage)
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let handle else {
            throw SPCDecoderError.initializationFailed
        }

        var interleaved = [Int16](repeating: 0, count: frameCount * 2)
        var renderedFrames: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = libvgm_player_render_s16(
            handle,
            Int32(frameCount),
            &interleaved,
            &renderedFrames,
            &errorMessage
        )
        try Self.throwIfNeeded(status, errorMessage: errorMessage)

        let actualFrameCount = max(0, Int(renderedFrames))
        var left = [Float](repeating: 0, count: actualFrameCount)
        var right = [Float](repeating: 0, count: actualFrameCount)

        for frame in 0..<actualFrameCount {
            let sourceIndex = frame * 2
            left[frame] = PCMFloatConversion.normalized(interleaved[sourceIndex])
            right[frame] = PCMFloatConversion.normalized(interleaved[sourceIndex + 1])
        }

        return DecodedChunk(left: left, right: right, frameCount: actualFrameCount)
    }

    static func trackMetadata(from rawMetadata: libvgm_metadata_t) -> TrackMetadata {
        TrackMetadata(
            game: string(from: rawMetadata.game),
            song: string(from: rawMetadata.title),
            system: string(from: rawMetadata.system),
            author: string(from: rawMetadata.artist),
            comment: string(from: rawMetadata.comment),
            introLengthMs: Int(rawMetadata.intro_length_ms),
            loopLengthMs: Int(rawMetadata.loop_length_ms),
            playLengthMs: Int(rawMetadata.play_length_ms),
            fadeLengthMs: Int(rawMetadata.fade_length_ms)
        )
    }

    static func throwIfNeeded(
        _ status: Int32,
        errorMessage: UnsafeMutablePointer<CChar>?
    ) throws {
        defer { freeErrorMessage(errorMessage) }

        guard status == 0 else {
            if let errorMessage {
                throw SPCDecoderError.library(String(cString: errorMessage))
            }
            throw SPCDecoderError.initializationFailed
        }
    }

    private static func string(from pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        let value = String(cString: pointer)
        return value == "?" ? "" : value
    }

    private static func freeErrorMessage(_ errorMessage: UnsafeMutablePointer<CChar>?) {
        guard let errorMessage else { return }
        libvgm_error_message_free(errorMessage)
    }
}

final class LibVGMFileInspector: AudioFileInspector {
    let trackCount: Int

    private let trackMetadata: TrackMetadata

    init(fileURL: URL) throws {
        var rawMetadata = libvgm_metadata_t()
        defer { libvgm_metadata_clear(&rawMetadata) }

        var rawTrackCount: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = fileURL.path.withCString { path in
            libvgm_inspect_file(path, &rawMetadata, &rawTrackCount, &errorMessage)
        }
        try LibVGMDecoder.throwIfNeeded(status, errorMessage: errorMessage)

        trackCount = max(1, Int(rawTrackCount))
        trackMetadata = LibVGMDecoder.trackMetadata(from: rawMetadata)
    }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard trackIndex == 0 else {
            throw SPCDecoderError.library("libvgm files currently expose a single playable track.")
        }
        return trackMetadata
    }
}

final class HighlyCompleteDecoder: AudioTrackDecoder {
    let sampleRate: Int
    let appliesFadeInternally = false

    private var handle: UnsafeMutableRawPointer?

    init(track: TrackItem, sampleRate: Int) throws {
        self.sampleRate = sampleRate
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)

        var errorMessage: UnsafeMutablePointer<CChar>?
        let createdHandle = HighlyCompleteBridgeGate.withLock {
            fileURL.path.withCString { path in
                highlycomplete_player_create(path, Int32(sampleRate), Int32(track.trackIndex), &errorMessage)
            }
        }
        guard let createdHandle else {
            defer { Self.freeErrorMessage(errorMessage) }
            if let errorMessage {
                throw SPCDecoderError.library(String(cString: errorMessage))
            }
            throw SPCDecoderError.initializationFailed
        }

        handle = createdHandle
    }

    deinit {
        if let handle {
            HighlyCompleteBridgeGate.withLock {
                highlycomplete_player_destroy(handle)
            }
        }
    }

    func metadata() throws -> TrackMetadata {
        guard let handle else {
            throw SPCDecoderError.initializationFailed
        }

        var rawMetadata = highlycomplete_metadata_t()
        defer { highlycomplete_metadata_clear(&rawMetadata) }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = HighlyCompleteBridgeGate.withLock {
            highlycomplete_player_read_metadata(handle, &rawMetadata, &errorMessage)
        }
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
        return Self.trackMetadata(from: rawMetadata)
    }

    var playedFrames: Int {
        guard let handle else {
            return 0
        }
        return HighlyCompleteBridgeGate.withLock {
            Int(highlycomplete_player_played_frames(handle))
        }
    }

    var trackEnded: Bool {
        guard let handle else { return true }
        return HighlyCompleteBridgeGate.withLock {
            highlycomplete_player_track_ended(handle) != 0
        }
    }

    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {
        guard let handle else { return }

        var errorMessage: UnsafeMutablePointer<CChar>?
        HighlyCompleteBridgeGate.withLock {
            _ = highlycomplete_player_configure(
                handle,
                Int32(loopSeconds),
                Int32(fadeSeconds),
                usesNativeEnding,
                &errorMessage
            )
        }
        Self.freeErrorMessage(errorMessage)
    }

    func seek(toMilliseconds milliseconds: Int) throws {
        guard let handle else {
            throw SPCDecoderError.initializationFailed
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = HighlyCompleteBridgeGate.withLock {
            highlycomplete_player_seek_milliseconds(handle, Int32(milliseconds), &errorMessage)
        }
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let handle else {
            throw SPCDecoderError.initializationFailed
        }

        var interleaved = [Int16](repeating: 0, count: frameCount * 2)
        var renderedFrames: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = HighlyCompleteBridgeGate.withLock {
            highlycomplete_player_render_s16(
                handle,
                Int32(frameCount),
                &interleaved,
                &renderedFrames,
                &errorMessage
            )
        }
        try Self.throwIfNeeded(status, errorMessage: errorMessage)

        let actualFrameCount = max(0, Int(renderedFrames))
        var left = [Float](repeating: 0, count: actualFrameCount)
        var right = [Float](repeating: 0, count: actualFrameCount)

        for frame in 0..<actualFrameCount {
            let sourceIndex = frame * 2
            left[frame] = PCMFloatConversion.normalized(interleaved[sourceIndex])
            right[frame] = PCMFloatConversion.normalized(interleaved[sourceIndex + 1])
        }

        return DecodedChunk(left: left, right: right, frameCount: actualFrameCount)
    }

    static func trackMetadata(from rawMetadata: highlycomplete_metadata_t) -> TrackMetadata {
        TrackMetadata(
            game: string(from: rawMetadata.game),
            song: string(from: rawMetadata.title),
            system: string(from: rawMetadata.system),
            author: string(from: rawMetadata.artist),
            comment: string(from: rawMetadata.comment),
            introLengthMs: Int(rawMetadata.intro_length_ms),
            loopLengthMs: Int(rawMetadata.loop_length_ms),
            playLengthMs: Int(rawMetadata.play_length_ms),
            fadeLengthMs: Int(rawMetadata.fade_length_ms)
        )
    }

    static func throwIfNeeded(
        _ status: Int32,
        errorMessage: UnsafeMutablePointer<CChar>?
    ) throws {
        defer { freeErrorMessage(errorMessage) }

        guard status == 0 else {
            if let errorMessage {
                throw SPCDecoderError.library(String(cString: errorMessage))
            }
            throw SPCDecoderError.initializationFailed
        }
    }

    private static func string(from pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }

    private static func freeErrorMessage(_ errorMessage: UnsafeMutablePointer<CChar>?) {
        guard let errorMessage else { return }
        highlycomplete_error_message_free(errorMessage)
    }
}

final class HighlyCompleteFileInspector: AudioFileInspector {
    let trackCount: Int

    private let trackMetadata: TrackMetadata

    init(fileURL: URL) throws {
        var rawMetadata = highlycomplete_metadata_t()
        defer { highlycomplete_metadata_clear(&rawMetadata) }

        var rawTrackCount: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = HighlyCompleteBridgeGate.withLock {
            fileURL.path.withCString { path in
                highlycomplete_inspect_file(path, &rawMetadata, &rawTrackCount, &errorMessage)
            }
        }
        try HighlyCompleteDecoder.throwIfNeeded(status, errorMessage: errorMessage)

        trackCount = max(1, Int(rawTrackCount))
        trackMetadata = HighlyCompleteDecoder.trackMetadata(from: rawMetadata)
    }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard trackIndex == 0 else {
            throw SPCDecoderError.library("HighlyComplete GSF files expose a single playable track.")
        }
        return trackMetadata
    }
}

final class LazyUSFDecoder: AudioTrackDecoder {
    let sampleRate: Int
    let appliesFadeInternally = false
    private var handle: lazyusf_player_handle_t?

    init(track: TrackItem, sampleRate: Int) throws {
        self.sampleRate = sampleRate
        let fileURL = try ZipArchiveSupport.materializePlayableFile(for: track)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let createdHandle = fileURL.path.withCString { path in
            lazyusf_player_create(path, Int32(sampleRate), &errorMessage)
        }
        guard let createdHandle else {
            defer { Self.freeErrorMessage(errorMessage) }
            if let errorMessage { throw SPCDecoderError.library(String(cString: errorMessage)) }
            throw SPCDecoderError.initializationFailed
        }
        handle = createdHandle
    }

    deinit {
        if let handle { lazyusf_player_destroy(handle) }
    }

    func metadata() throws -> TrackMetadata {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var rawMetadata = lazyusf_metadata_t()
        defer { lazyusf_metadata_clear(&rawMetadata) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = lazyusf_player_read_metadata(handle, &rawMetadata, &errorMessage)
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
        return Self.trackMetadata(from: rawMetadata)
    }

    var playedFrames: Int {
        guard let handle else { return 0 }
        return Int(lazyusf_player_played_frames(handle))
    }

    var trackEnded: Bool { false }

    func configurePlayback(loopSeconds: Int, fadeSeconds: Int, usesNativeEnding: Bool) {}

    func seek(toMilliseconds milliseconds: Int) throws {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = lazyusf_player_seek_milliseconds(handle, Int32(milliseconds), &errorMessage)
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
    }

    func decode(frameCount: Int) throws -> DecodedChunk {
        guard let handle else { throw SPCDecoderError.initializationFailed }
        var interleaved = [Int16](repeating: 0, count: frameCount * 2)
        var renderedFrames: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = lazyusf_player_render_s16(handle, Int32(frameCount), &interleaved, &renderedFrames, &errorMessage)
        try Self.throwIfNeeded(status, errorMessage: errorMessage)
        let actualFrameCount = max(0, Int(renderedFrames))
        var left = [Float](repeating: 0, count: actualFrameCount)
        var right = [Float](repeating: 0, count: actualFrameCount)
        for frame in 0..<actualFrameCount {
            let sourceIndex = frame * 2
            left[frame] = PCMFloatConversion.normalized(interleaved[sourceIndex])
            right[frame] = PCMFloatConversion.normalized(interleaved[sourceIndex + 1])
        }
        return DecodedChunk(left: left, right: right, frameCount: actualFrameCount)
    }

    static func trackMetadata(from rawMetadata: lazyusf_metadata_t) -> TrackMetadata {
        TrackMetadata(
            game: string(from: rawMetadata.game),
            song: string(from: rawMetadata.title),
            system: string(from: rawMetadata.system),
            author: string(from: rawMetadata.artist),
            comment: string(from: rawMetadata.comment),
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: Int(rawMetadata.play_length_ms),
            fadeLengthMs: Int(rawMetadata.fade_length_ms)
        )
    }

    private static func string(from pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }

    static func throwIfNeeded(_ status: Int32, errorMessage: UnsafeMutablePointer<CChar>?) throws {
        defer { freeErrorMessage(errorMessage) }
        guard status == 0 else {
            if let errorMessage { throw SPCDecoderError.library(String(cString: errorMessage)) }
            throw SPCDecoderError.initializationFailed
        }
    }

    private static func freeErrorMessage(_ errorMessage: UnsafeMutablePointer<CChar>?) {
        guard let errorMessage else { return }
        lazyusf_error_message_free(errorMessage)
    }
}

final class LazyUSFFileInspector: AudioFileInspector {
    let trackCount = 1
    private let trackMetadata: TrackMetadata

    init(fileURL: URL) throws {
        var rawMetadata = lazyusf_metadata_t()
        defer { lazyusf_metadata_clear(&rawMetadata) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = fileURL.path.withCString { path in
            lazyusf_inspect_metadata(path, &rawMetadata, &errorMessage)
        }
        try LazyUSFDecoder.throwIfNeeded(status, errorMessage: errorMessage)
        trackMetadata = LazyUSFDecoder.trackMetadata(from: rawMetadata)
    }

    func metadata(trackIndex: Int) throws -> TrackMetadata {
        guard trackIndex == 0 else { throw SPCDecoderError.library("USF files expose a single playable track.") }
        return trackMetadata
    }
}
