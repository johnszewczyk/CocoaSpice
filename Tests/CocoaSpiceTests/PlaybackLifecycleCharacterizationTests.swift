import Foundation
import Testing
@testable import CocoaSpice

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
