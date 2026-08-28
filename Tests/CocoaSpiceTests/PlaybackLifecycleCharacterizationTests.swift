import AudioToolbox
import Foundation
import Testing
@testable import CocoaSpice
import VGMBoyKit

private final class AACProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AACExportProgress?

    var last: AACExportProgress? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ progress: AACExportProgress) {
        lock.lock()
        stored = progress
        lock.unlock()
    }
}

@MainActor
@Test
func playbackRequestSupersessionReplacesTheOlderFrontendRequest() {
    let requests = PlaybackRequestState()
    let firstTrack = TrackItem(url: URL(fileURLWithPath: "/tmp/first.spc"))
    let secondTrack = TrackItem(url: URL(fileURLWithPath: "/tmp/second.spc"))
    let firstGeneration = requests.begin(track: firstTrack)
    requests.reachedEnd = true
    let secondGeneration = requests.begin(track: secondTrack)

    #expect(secondGeneration != firstGeneration)
    #expect(!requests.isCurrent(firstGeneration))
    #expect(requests.isCurrent(secondGeneration))
    #expect(requests.pendingTrack?.id == secondTrack.id)
    #expect(!requests.reachedEnd)
}

@MainActor
@Test
func playbackRequestCancellationClearsOnlyTheDefaultPendingTrack() {
    let requests = PlaybackRequestState()
    let track = TrackItem(url: URL(fileURLWithPath: "/tmp/pending.spc"))

    _ = requests.begin(track: track)
    requests.cancel(clearPendingTrack: false)
    #expect(requests.pendingTrack?.id == track.id)

    requests.cancel()
    #expect(requests.pendingTrack == nil)
}

@MainActor
@Test
func playbackAdapterStateAllowsConcurrentTrackSnapshotReplacement() {
    let state = PlaybackAdapterState()

    DispatchQueue.concurrentPerform(iterations: 8) { worker in
        for index in 0..<500 {
            state.currentTrack = TrackItem(
                url: URL(fileURLWithPath: "/tmp/worker-\(worker)-\(index).spc")
            )
            _ = state.currentTrack?.id
        }
    }

    #expect(state.currentTrack != nil)
}

@MainActor
@Test
func selectedCatalogMetadataDrivesPrePlaybackDurationReadout() {
    let model = PlayerViewModel()
    let track = TrackItem(
        archiveURL: URL(fileURLWithPath: "/tmp/Resident Evil 2.tar.zst"),
        entryPath: "11 Secure Place.psf"
    )
    let staleTrack = TrackItem(
        archiveURL: URL(fileURLWithPath: "/tmp/Resident Evil 2.tar.zst"),
        entryPath: "16 T-A.psf"
    )
    model.playlist = [track, staleTrack]
    model.metadataCache = [track.id: TrackMetadata(
        game: "Resident Evil 2",
        song: "Secure Place",
        system: "Sony PlayStation",
        author: "",
        comment: "",
        introLengthMs: 0,
        loopLengthMs: 0,
        playLengthMs: 43_000,
        fadeLengthMs: 10_000
    ), staleTrack.id: TrackMetadata(
        game: "Resident Evil 2",
        song: "T-A",
        system: "Sony PlayStation",
        author: "",
        comment: "",
        introLengthMs: 0,
        loopLengthMs: 0,
        playLengthMs: 69_000,
        fadeLengthMs: 10_000
    )]
    model.selectedTrackID = track.id
    model.currentTrack = staleTrack
    model.currentMetadata = nil
    model.endFadeEnabled = false

    #expect(model.currentTrackDurationReadout == "0:43")
}

@MainActor
@Test(
    "Resident Evil 2 archive reaches the shared VGMBoy transport",
    .enabled(
        if: ProcessInfo.processInfo.environment["COCOASPICE_RE2_ARCHIVE"] != nil,
        "Set COCOASPICE_RE2_ARCHIVE to run the real archive-to-transport check."
    )
)
func residentEvil2ArchiveReplacesPlaybackThroughVGMBoy() async throws {
    let archivePath = try #require(ProcessInfo.processInfo.environment["COCOASPICE_RE2_ARCHIVE"])
    let track = TrackItem(
        archiveURL: URL(fileURLWithPath: archivePath),
        entryPath: "11 Secure Place.psf"
    )
    let engine = PlaybackEngine()
    defer { ZipArchiveSupport.discardDisposablePlaybackMaterialization() }

    try await engine.play(
        track: track,
        plan: PlaybackPlan(preFadeSeconds: 150, fadeSeconds: 0, usesNativeEnding: true, isLongPlay: false),
        tempo: .defaultValue,
        requestID: engine.reservePlaybackRequest()
    )
    let status = await engine.statusSnapshot()
    #expect(engine.currentTrack?.id == track.id)
    #expect(status.currentTrackID == track.id)
    #expect(status.isPlaying)
    await engine.stop()
}

@MainActor
@Test(
    "AAC export renders an archive-backed RE2 track",
    .enabled(
        if: ProcessInfo.processInfo.environment["COCOASPICE_AAC_ARCHIVE"] != nil,
        "Set COCOASPICE_AAC_ARCHIVE to run the real archive AAC check."
    )
)
func archiveBackedAACExportProducesFiniteOutput() async throws {
    let archivePath = try #require(ProcessInfo.processInfo.environment["COCOASPICE_AAC_ARCHIVE"])
    let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CocoaSpice-AAC-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDirectory) }

    let engine = PlaybackEngine()
    let track = TrackItem(
        archiveURL: URL(fileURLWithPath: archivePath),
        entryPath: "11 Secure Place.psf"
    )
    let cancellation = AACExportCancellation()
    let progressBox = AACProgressBox()
    let output = try await engine.exportAAC(
        track: track,
        plan: PlaybackPlan(preFadeSeconds: 2, fadeSeconds: 0, usesNativeEnding: true, isLongPlay: false),
        outputDirectory: outputDirectory,
        filenameStem: "re2-aac-fixture",
        cancellation: cancellation,
        progress: { progress in progressBox.record(progress) }
    )

    let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
    #expect(FileManager.default.fileExists(atPath: output.path))
    #expect((attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0)
    #expect(progressBox.last?.fractionComplete == 1)

    var audioFile: AudioFileID?
    #expect(AudioFileOpenURL(output as CFURL, .readPermission, kAudioFileAAC_ADTSType, &audioFile) == noErr)
    if let audioFile { AudioFileClose(audioFile) }
}

@MainActor
@Test(
    "Doom archive track changes remain stable across both source sets",
    .enabled(
        if: ProcessInfo.processInfo.environment["COCOASPICE_DOOM_JOSHW_ARCHIVE"] != nil
            && ProcessInfo.processInfo.environment["COCOASPICE_DOOM_SNESMUSICORG_ARCHIVE"] != nil,
        "Set both Doom archive environment variables to run the real archive transition check."
    )
)
func doomArchiveTrackChangesRemainStable() async throws {
    let archivePaths = [
        try #require(ProcessInfo.processInfo.environment["COCOASPICE_DOOM_JOSHW_ARCHIVE"]),
        try #require(ProcessInfo.processInfo.environment["COCOASPICE_DOOM_SNESMUSICORG_ARCHIVE"])
    ]
    let tracks = try archivePaths.flatMap { path in
        try ZipArchiveSupport.listPlayableEntries(
            in: URL(fileURLWithPath: path),
            supportedExtensions: PlaybackFormatRegistry.supportedExtensions
        ).map { entry in
            TrackItem(archiveURL: entry.archiveURL, entryPath: entry.entryPath)
        }
    }
    #expect(tracks.count >= 16)

    let engine = PlaybackEngine()
    for track in tracks.prefix(16) {
        try await engine.play(
            track: track,
            plan: PlaybackPlan(preFadeSeconds: 150, fadeSeconds: 0, usesNativeEnding: false, isLongPlay: false),
            tempo: .defaultValue,
            requestID: engine.reservePlaybackRequest()
        )
        let status = await engine.statusSnapshot()
        #expect(status.currentTrackID == track.id)
        #expect(status.isPlaying)
    }
    await engine.stop()
}
