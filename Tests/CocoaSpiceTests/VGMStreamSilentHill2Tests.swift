import Foundation
import Testing
@testable import CocoaSpice

@Test func vgmstreamDecodesSilentHill2IECSAndSVAGArchiveMembers() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain/PSF2/Silent Hill 2 (EMU).zophar.tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    for entryPath in ["SOUND_X_1.iecs", "SOUND_1.svag"] {
        let decoder = try VGMStreamDecoder(
            track: TrackItem(archiveURL: archiveURL, entryPath: entryPath),
            sampleRate: 44_100
        )
        let metadata = try decoder.metadata()
        let chunk = try decoder.decode(frameCount: 2_048)

        #expect(metadata.system == "PlayStation 2")
        #expect(chunk.frameCount == 2_048, "\(entryPath) did not produce PCM")
    }
}

@Test func vgmstreamSVAGUsesTheSharedExternalFade() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain/PSF2/Silent Hill 2 (EMU).zophar.tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let track = TrackItem(archiveURL: archiveURL, entryPath: "SOUND_1.svag")
    let rawDecoder = try VGMStreamDecoder(track: track, sampleRate: 44_100)
    let chunkFrames = max(1, rawDecoder.sampleRate / 10)
    let session = try PlaybackStreamSession(
        track: track,
        sampleRate: rawDecoder.sampleRate,
        totalSeconds: 2,
        loopSeconds: 1,
        fadeSeconds: 1,
        isLongPlay: false,
        chunkFrameCount: chunkFrames
    )

    for _ in 0..<15 {
        let buffer = try session.makeNextBuffer(
            sampleRate: Double(rawDecoder.sampleRate),
            channels: 2
        )
        _ = try #require(buffer)
    }
    let maybeFadedBuffer = try session.makeNextBuffer(
        sampleRate: Double(rawDecoder.sampleRate),
        channels: 2
    )
    let fadedBuffer = try #require(maybeFadedBuffer)
    try rawDecoder.seek(toMilliseconds: 1_500)
    let rawChunk = try rawDecoder.decode(frameCount: chunkFrames)

    let fadedSamples = Array(UnsafeBufferPointer(
        start: fadedBuffer.floatChannelData![0],
        count: Int(fadedBuffer.frameLength)
    ))
    let rawEnergy = rawChunk.left.reduce(Float.zero) { $0 + abs($1) }
    let fadedEnergy = fadedSamples.reduce(Float.zero) { $0 + abs($1) }
    #expect(rawEnergy > 0)
    let ratio = fadedEnergy / rawEnergy
    #expect(ratio > 0.35 && ratio < 0.55, "expected midpoint fade, got \(ratio)")
}

@Test func deepScanRecognizesEveryPlayableSilentHill2Stream() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain/PSF2/Silent Hill 2 (EMU).zophar.tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: archiveURL.path, archiveEntry: nil),
        fingerprint: ScanFingerprint(
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast
        ),
        sourceURL: archiveURL,
        route: nil
    )

    let accumulator = try await ScanPipelineExecutor().process(
        plan: ScanPlan(mode: .newScan, candidates: [candidate]),
        persist: { _ in }
    )
    let summary = await accumulator.summary

    #expect(summary.completed == 188)
    #expect(summary.successful == 188)
    #expect(summary.failed == 0)
    #expect(summary.unsupported == 0)
}
