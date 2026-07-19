@preconcurrency import AVFoundation
import AppKit
import AudioToolbox
import CoreMedia
import Foundation

struct AudioExportRequest: Sendable {
    let track: TrackItem
    let metadata: TrackMetadata
    let plan: PlaybackPlan
    let outputURL: URL
}

struct AudioExportProgressSnapshot: Sendable {
    let title: String
    let detail: String
    let progress: Double?
}

struct AudioExportBatchResult: Sendable {
    let exportedCount: Int
    let outputDirectory: URL
}

enum AudioExportError: LocalizedError {
    case writerInitializationFailed
    case writerInputRejected
    case writerStartFailed(String)
    case appendFailed(String)
    case sampleBufferCreationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .writerInitializationFailed:
            return "The AAC writer could not be created."
        case .writerInputRejected:
            return "The AAC writer rejected the audio input settings."
        case .writerStartFailed(let message):
            return "The AAC writer failed to start: \(message)"
        case .appendFailed(let message):
            return "The AAC writer failed while writing audio: \(message)"
        case .sampleBufferCreationFailed(let status):
            return "The AAC writer could not build a sample buffer (\(status))."
        }
    }
}

enum AudioExportAACService {
    static let sampleRate = 44_100
    static let channels: AVAudioChannelCount = 2
    static let bitrate = 256_000
    static let chunkFrameCount = 16_384

    @MainActor
    static func makeDestinationFolderPanel(defaultDirectory: URL?) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = "Choose AAC Export Folder"
        panel.prompt = "Export"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = defaultDirectory
        return panel
    }

    static func buildRequests(
        tracks: [TrackItem],
        cachedMetadata: [String: TrackMetadata],
        outputDirectory: URL,
        longPlayEnabled: Bool,
        manualPreFadeSeconds: Int,
        fadeSeconds: Int
    ) async throws -> [AudioExportRequest] {
        var requests: [AudioExportRequest] = []
        requests.reserveCapacity(tracks.count)

        for track in tracks {
            let metadata = if let cached = cachedMetadata[track.id] {
                cached
            } else {
                try await PlaybackInspection.inspectMetadata(track: track)
            }

            let plan = PlaybackTimingPolicy.playbackPlan(
                metadata: metadata,
                trackPathExtension: track.playablePathExtension,
                longPlayEnabled: longPlayEnabled,
                manualPreFadeSeconds: manualPreFadeSeconds,
                fadeSeconds: fadeSeconds
            )

            let outputURL = uniqueOutputURL(
                in: outputDirectory,
                preferredBaseName: preferredBaseName(for: track, metadata: metadata)
            )

            requests.append(
                AudioExportRequest(
                    track: track,
                    metadata: metadata,
                    plan: plan,
                    outputURL: outputURL
                )
            )
        }

        return requests
    }

    static func export(
        requests: [AudioExportRequest],
        progress: @escaping @Sendable (AudioExportProgressSnapshot) -> Void
    ) async throws -> AudioExportBatchResult {
        guard let firstRequest = requests.first else {
            return AudioExportBatchResult(exportedCount: 0, outputDirectory: URL(fileURLWithPath: "/"))
        }

        let totalTracks = requests.count
        for (index, request) in requests.enumerated() {
            let expectedFrames = expectedFrameCount(metadata: request.metadata, plan: request.plan)
            let positionLabel = "\(index + 1)/\(totalTracks)"

            progress(
                AudioExportProgressSnapshot(
                    title: "Exporting \(positionLabel)",
                    detail: request.outputURL.path,
                    progress: totalTracks == 1 ? 0 : Double(index) / Double(totalTracks)
                )
            )

            let session = try AudioExportStreamSession(
                track: request.track,
                plan: request.plan,
                sampleRate: sampleRate,
                channels: channels,
                chunkFrameCount: chunkFrameCount
            )
            let writer = try AACFileWriter(
                outputURL: request.outputURL,
                metadata: request.metadata,
                sampleRate: sampleRate,
                channels: channels,
                bitrate: bitrate
            )

            var lastUpdateTime: TimeInterval = 0
            while let buffer = try session.makeNextBuffer() {
                try await writer.append(buffer)

                let now = Date().timeIntervalSinceReferenceDate
                if now - lastUpdateTime >= 0.05 {
                    let trackProgress = expectedFrames.map { frames in
                        min(Double(session.playedFrames) / Double(max(frames, 1)), 1)
                    }
                    let overallProgress = trackProgress.map {
                        (Double(index) + $0) / Double(totalTracks)
                    } ?? (totalTracks == 1 ? nil : Double(index) / Double(totalTracks))

                    progress(
                        AudioExportProgressSnapshot(
                            title: "Exporting \(positionLabel)",
                            detail: request.outputURL.path,
                            progress: overallProgress
                        )
                    )
                    lastUpdateTime = now
                }
            }

            try await writer.finish()

            progress(
                AudioExportProgressSnapshot(
                    title: "Exported \(positionLabel)",
                    detail: request.outputURL.path,
                    progress: Double(index + 1) / Double(totalTracks)
                )
            )
        }

        return AudioExportBatchResult(
            exportedCount: requests.count,
            outputDirectory: firstRequest.outputURL.deletingLastPathComponent()
        )
    }

    private static func preferredBaseName(for track: TrackItem, metadata: TrackMetadata) -> String {
        let gameName = metadata.game.nonEmpty ?? track.groupDisplayName
        let title = metadata.song.nonEmpty ?? track.displayName
        let trackNumber = String(format: "%02d", track.displayTrackNumber)
        return "\(gameName) - \(trackNumber) - \(title)"
    }

    private static func uniqueOutputURL(in directory: URL, preferredBaseName: String) -> URL {
        let cleanedBaseName = sanitizeFilename(preferredBaseName)
        var candidate = directory.appendingPathComponent(cleanedBaseName).appendingPathExtension("m4a")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(cleanedBaseName) \(suffix)")
                .appendingPathExtension("m4a")
            suffix += 1
        }
        return candidate
    }

    private static func sanitizeFilename(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Exported Track" : trimmed
        let invalidScalars = CharacterSet(charactersIn: "/:\\?%*|\"<>\n\r\t")
        let cleaned = fallback.unicodeScalars.map { scalar in
            invalidScalars.contains(scalar) ? "_" : Character(scalar)
        }
        let collapsed = String(cleaned)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return collapsed.isEmpty ? "Exported Track" : collapsed
    }

    private static func expectedFrameCount(metadata: TrackMetadata, plan: PlaybackPlan) -> Int? {
        if !plan.usesNativeEnding {
            return max(plan.totalSeconds * sampleRate, 1)
        }

        if metadata.playLengthMs > 0 {
            return max(Int((Double(metadata.playLengthMs) / 1_000.0) * Double(sampleRate)), 1)
        }

        let introAndLoop = max(metadata.introLengthMs + metadata.loopLengthMs, metadata.loopLengthMs)
        if introAndLoop > 0 {
            return max(Int((Double(introAndLoop) / 1_000.0) * Double(sampleRate)), 1)
        }

        return nil
    }
}

private final class AudioExportStreamSession {
    private let decoder: any AudioTrackDecoder
    private let totalFrames: Int?
    private let fadeFrameCount: Int
    private let chunkFrameCount: Int
    private let format: AVAudioFormat

    init(
        track: TrackItem,
        plan: PlaybackPlan,
        sampleRate: Int,
        channels: AVAudioChannelCount,
        chunkFrameCount: Int
    ) throws {
        decoder = try PlaybackDecoderFactory.makeDecoder(track: track, sampleRate: sampleRate)
        totalFrames = plan.usesNativeEnding ? nil : max(plan.totalSeconds * sampleRate, 1)
        fadeFrameCount = max(0, plan.fadeSeconds * sampleRate)
        self.chunkFrameCount = chunkFrameCount
        format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: channels)!
        decoder.setLongPlayEnabled(plan.isLongPlay)
        decoder.configurePlayback(
            loopSeconds: plan.preFadeSeconds,
            fadeSeconds: plan.fadeSeconds,
            usesNativeEnding: plan.usesNativeEnding
        )
    }

    var playedFrames: Int {
        decoder.playedFrames
    }

    func makeNextBuffer() throws -> AVAudioPCMBuffer? {
        if totalFrames == nil, decoder.trackEnded {
            return nil
        }

        let playedFrames = decoder.playedFrames
        if let totalFrames {
            guard playedFrames < totalFrames else { return nil }
        }

        let frameCount: Int
        if let totalFrames {
            frameCount = min(chunkFrameCount, totalFrames - playedFrames)
        } else {
            frameCount = chunkFrameCount
        }

        let chunkStartFrame = playedFrames
        let chunk = try decoder.decode(frameCount: frameCount)
        guard chunk.frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(chunk.frameCount)
        ) else {
            throw SPCDecoderError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(chunk.frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        chunk.left.withUnsafeBufferPointer { source in
            left.update(from: source.baseAddress!, count: chunk.frameCount)
        }
        chunk.right.withUnsafeBufferPointer { source in
            right.update(from: source.baseAddress!, count: chunk.frameCount)
        }

        if let totalFrames, !decoder.appliesFadeInternally, fadeFrameCount > 0 {
            applyExternalFade(
                to: buffer,
                frameCount: chunk.frameCount,
                chunkStartFrame: chunkStartFrame,
                totalFrames: totalFrames
            )
        }

        return buffer
    }

    private func applyExternalFade(
        to buffer: AVAudioPCMBuffer,
        frameCount: Int,
        chunkStartFrame: Int,
        totalFrames: Int
    ) {
        let fadeStartFrame = max(0, totalFrames - fadeFrameCount)
        guard chunkStartFrame + frameCount > fadeStartFrame else { return }

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for frameOffset in 0..<frameCount {
            let absoluteFrame = chunkStartFrame + frameOffset
            guard absoluteFrame >= fadeStartFrame else { continue }

            let remainingFrames = max(totalFrames - absoluteFrame, 0)
            let gain = Float(remainingFrames) / Float(max(fadeFrameCount, 1))
            left[frameOffset] *= gain
            right[frameOffset] *= gain
        }
    }
}

private final class AACFileWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let sampleRate: Int
    private var nextPresentationFrame: Int64 = 0

    init(
        outputURL: URL,
        metadata: TrackMetadata,
        sampleRate: Int,
        channels: AVAudioChannelCount,
        bitrate: Int
    ) throws {
        try? FileManager.default.removeItem(at: outputURL)
        self.sampleRate = sampleRate

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channels),
            AVEncoderBitRateKey: bitrate
        ]
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else {
            throw AudioExportError.writerInputRejected
        }

        writer.add(input)
        writer.metadata = Self.metadataItems(for: metadata)

        guard writer.startWriting() else {
            throw AudioExportError.writerStartFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ buffer: AVAudioPCMBuffer) async throws {
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(1))
        }

        let presentationTime = CMTime(value: nextPresentationFrame, timescale: CMTimeScale(sampleRate))
        let sampleBuffer = try makeSampleBuffer(from: buffer, presentationTime: presentationTime)
        guard input.append(sampleBuffer) else {
            throw AudioExportError.appendFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
        nextPresentationFrame += Int64(buffer.frameLength)
    }

    func finish() async throws {
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed else {
            throw AudioExportError.appendFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
    }

    private func makeSampleBuffer(
        from buffer: AVAudioPCMBuffer,
        presentationTime: CMTime
    ) throws -> CMSampleBuffer {
        let formatDescription = buffer.format.formatDescription

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw AudioExportError.sampleBufferCreationFailed(status)
        }

        let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: buffer.audioBufferList
        )
        guard setStatus == noErr else {
            throw AudioExportError.sampleBufferCreationFailed(setStatus)
        }

        let readyStatus = CMSampleBufferSetDataReady(sampleBuffer)
        guard readyStatus == noErr else {
            throw AudioExportError.sampleBufferCreationFailed(readyStatus)
        }

        return sampleBuffer
    }

    private static func metadataItems(for metadata: TrackMetadata) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        if let song = metadata.song.nonEmpty {
            items.append(metadataItem(key: .iTunesMetadataKeySongName, value: song))
        }
        if let artist = metadata.author.nonEmpty {
            items.append(metadataItem(key: .iTunesMetadataKeyArtist, value: artist))
        }
        if let album = metadata.game.nonEmpty {
            items.append(metadataItem(key: .iTunesMetadataKeyAlbum, value: album))
        }
        if let genre = metadata.system.nonEmpty {
            items.append(metadataItem(key: .iTunesMetadataKeyUserGenre, value: genre))
        }
        if let comment = metadata.comment.nonEmpty {
            items.append(metadataItem(key: .iTunesMetadataKeyUserComment, value: comment))
        }

        return items
    }

    private static func metadataItem(key: AVMetadataKey, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .iTunes
        item.key = key as (NSCopying & NSObjectProtocol)
        item.value = value as (NSCopying & NSObjectProtocol)
        return item.copy() as! AVMetadataItem
    }
}
