import AppKit
import C2SF
import Foundation
import Testing
@testable import CocoaSpice

@Test func supportedExtensionsIncludeLinkedLibGMETypes() {
    #expect(SPCFileScanner.supportedExtensions.contains("ay"))
    #expect(SPCFileScanner.supportedExtensions.contains("gbs"))
    #expect(SPCFileScanner.supportedExtensions.contains("hes"))
    #expect(SPCFileScanner.supportedExtensions.contains("kss"))
    #expect(SPCFileScanner.supportedExtensions.contains("nsf"))
    #expect(SPCFileScanner.supportedExtensions.contains("nsfe"))
    #expect(SPCFileScanner.supportedExtensions.contains("sap"))
    #expect(SPCFileScanner.supportedExtensions.contains("spc"))
    #expect(SPCFileScanner.supportedExtensions.contains("vgm"))
    #expect(SPCFileScanner.supportedExtensions.contains("vgz"))
    #expect(SPCFileScanner.supportedExtensions.contains("gsf"))
    #expect(SPCFileScanner.supportedExtensions.contains("minigsf"))
    #expect(SPCFileScanner.supportedExtensions.contains("usf"))
    #expect(SPCFileScanner.supportedExtensions.contains("miniusf"))
    #expect(SPCFileScanner.supportedExtensions.contains("2sf"))
    #expect(SPCFileScanner.supportedExtensions.contains("mini2sf"))
    #expect(!SPCFileScanner.supportedExtensions.contains("nds"))
}

@Test func twoSFUsesItsDedicatedDecoderRoute() {
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "2SF") == .twoSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "mini2sf") == .twoSF)
}

@Test func twoSFReconfigurationKeepsTheReplacementCoreAlive() {
    let fileURL = URL(fileURLWithPath: "/tmp/cocoaspice-2sf-repro/01 Prologue.mini2sf")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    var errorMessage: UnsafeMutablePointer<CChar>?
    let handle = fileURL.path.withCString { twosf_player_create($0, 44_100, &errorMessage) }
    defer { if let handle { twosf_player_destroy(handle) } }
    defer { if let errorMessage { twosf_error_message_free(errorMessage) } }
    guard let handle else {
        Issue.record("Could not open local 2SF reproduction fixture")
        return
    }

    #expect(twosf_player_configure(handle, 115_000, 5_000, &errorMessage) == 0)
    var samples = [Int16](repeating: 0, count: 2_048)
    var rendered: Int32 = 0
    #expect(twosf_player_render_s16(handle, 1_024, &samples, &rendered, &errorMessage) == 0)
    #expect(rendered > 0)
}

@Test func archiveMiniGSFLoadsItsSiblingLibrary() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/GSF/Ace Combat Advance (2005-02-23)(Human Soft)(Namco)[GBA].7z")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let decoder = try HighlyCompleteDecoder(
        track: TrackItem(archiveURL: archiveURL, entryPath: "01 BGM #01.minigsf"),
        sampleRate: 44_100
    )
    let chunk = try decoder.decode(frameCount: 1_024)
    #expect(chunk.frameCount > 0)
}

@Test func scannedSPCInspectionSuppliesThePlaybackDuration() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/SPC/0-9/3 Ninjas Kick Back (1994-11)(Malibu)(Sony Imagesoft)[SNES].7z")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
    guard let entry = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: ["spc"]
    ).first else {
        Issue.record("Expected an SPC entry in the local fixture archive")
        return
    }

    guard let route = ScanCoreHandlers.registry.route(for: "spc", archiveMember: true) else {
        Issue.record("SPC should be registered for archive scanning")
        return
    }
    let materializedURL = try ZipArchiveSupport.materializeEntry(
        archiveURL: archiveURL,
        entryPath: entry.entryPath
    )
    let inspection = try await DecoderCoreScanHandler(descriptor: ScanPluginDescriptor(
        pluginID: "gme",
        displayName: "Game Music Emu",
        supportedExtensions: GMEFormatSupport.libGMESupportedExtensions,
        supportsMultiTrack: true,
        priority: 10
    ))
        .inspect(fileURL: materializedURL, route: route)
    let duration = inspection.tracks.first?.metadata?.playLengthMs ?? 0
    #expect(duration > 0)
}

@Test func supportedExtensionsPreserveLegacyS98Compatibility() {
    #expect(SPCFileScanner.supportedExtensions.contains("s98"))
}

@Test func scanRegistryRoutesByPriorityAndNormalizesExtensions() {
    let registry = ScanPluginRegistry(descriptors: [
        ScanPluginDescriptor(
            pluginID: "fallback",
            displayName: "Fallback",
            supportedExtensions: ["vgm"],
            priority: 1
        ),
        ScanPluginDescriptor(
            pluginID: "preferred",
            displayName: "Preferred",
            supportedExtensions: [".VGM"],
            supportsMultiTrack: true,
            priority: 2
        )
    ])

    let route = registry.route(for: ".VGM", archiveMember: true)
    #expect(route?.pluginID == "preferred")
    #expect(route?.formatExtension == "vgm")
    #expect(route?.supportsMultiTrack == true)
}

@Test func scanSelectionSeparatesNewRetryAndIncrementalModes() {
    let identity = ScanItemIdentity(rootID: 1, path: "/music/set.gbs", archiveEntry: "song.gbs")
    let fingerprint = ScanFingerprint(fileSize: 10, modifiedAt: Date(timeIntervalSince1970: 1))
    let changed = ScanFingerprint(fileSize: 11, modifiedAt: Date(timeIntervalSince1970: 2))

    let successful = ScanInventoryItem(identity: identity, fingerprint: fingerprint, state: .successful, route: nil)
    let failed = ScanInventoryItem(identity: identity, fingerprint: fingerprint, state: .failed, route: nil)

    #expect(!ScanSelection.includes(successful, mode: .incremental, currentFingerprint: fingerprint))
    #expect(ScanSelection.includes(successful, mode: .incremental, currentFingerprint: changed))
    #expect(ScanSelection.includes(failed, mode: .retryFailed, currentFingerprint: fingerprint))
    #expect(!ScanSelection.includes(successful, mode: .retryFailed, currentFingerprint: fingerprint))
    #expect(ScanSelection.includes(successful, mode: .newScan, currentFingerprint: fingerprint))
}

@Test func scanPlannerOnlySchedulesSelectedItemsInStableOrder() {
    let fingerprint = ScanFingerprint(fileSize: 1, modifiedAt: Date(timeIntervalSince1970: 1))
    let first = ScanItemIdentity(rootID: 1, path: "/music/z.7z", archiveEntry: "z.gbs")
    let second = ScanItemIdentity(rootID: 1, path: "/music/a.7z", archiveEntry: "a.gbs")
    let items = [
        ScanInventoryItem(identity: first, fingerprint: fingerprint, state: .successful, route: nil),
        ScanInventoryItem(identity: second, fingerprint: fingerprint, state: .failed, route: nil)
    ]
    let urls = [
        first: URL(fileURLWithPath: first.path),
        second: URL(fileURLWithPath: second.path)
    ]

    let plan = ScanPlanner.makePlan(
        mode: .retryFailed,
        items: items,
        sourceURLs: urls,
        currentFingerprints: [:]
    )

    #expect(plan.count == 1)
    #expect(plan.candidates.first?.identity == second)
}

@Test func scanResourceSchedulerReleasesPermitsAfterFailure() async throws {
    let scheduler = ScanResourceScheduler(permits: 1)
    do {
        _ = try await scheduler.withPermit {
            throw CocoaSpiceTestError.expected
        } as Void
        Issue.record("Expected scheduler operation to throw")
    } catch CocoaSpiceTestError.expected {
        // Expected; the permit must still be available below.
    }

    let value = try await scheduler.withPermit { 42 }
    #expect(value == 42)
}

@Test func scanResourceSchedulerDoesNotRunBlockingWorkOnItsActor() async throws {
    let scheduler = ScanResourceScheduler(permits: 2)
    let startedAt = Date()

    async let first: Int = scheduler.withPermit {
        let deadline = Date().addingTimeInterval(0.15)
        while Date() < deadline {}
        return 1
    }
    async let second: Int = scheduler.withPermit {
        let deadline = Date().addingTimeInterval(0.15)
        while Date() < deadline {}
        return 2
    }

    #expect(try await [first, second] == [1, 2])
    #expect(Date().timeIntervalSince(startedAt) < 0.25)
}

@Test func scanOperationTimeoutReturnsBeforeThirtySecondLimitForCompletedWork() async throws {
    let value = try await ScanOperationTimeout.run(description: "test") { 7 }
    #expect(value == 7)
}

@Test func scanPipelineProcessesFirstJoshWSPCArchive() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/SPC/0-9/3 Ninjas Kick Back (1994-11)(Malibu)(Sony Imagesoft)[SNES].7z")
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
    let executor = ScanPipelineExecutor()
    let accumulator = try await executor.process(
        plan: ScanPlan(mode: .newScan, candidates: [candidate]),
        persist: { _ in }
    )
    let summary = await accumulator.summary
    #expect(summary.completed > 0)
    #expect(summary.successful > 0)
}

@Test func scanPipelineProcessesFirstEightJoshWSPCArchivesConcurrently() async throws {
    let rootURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/SPC")
    guard FileManager.default.fileExists(atPath: rootURL.path) else { return }

    let candidates = await ScanFilesystemDiscovery.discover(
        rootID: 1,
        rootURL: rootURL,
        registry: ScanCoreHandlers.registry
    ).prefix(8)
    #expect(candidates.count == 8)

    let accumulator = try await ScanPipelineExecutor().process(
        plan: ScanPlan(mode: .newScan, candidates: Array(candidates)),
        persist: { _ in }
    )
    let summary = await accumulator.summary
    #expect(summary.completed > 0)
    #expect(summary.successful > 0)
}

@Test @MainActor func scanPipelineCommandLineProbe() async throws {
    guard let rootPath = ProcessInfo.processInfo.environment["COCOASPICE_SCAN_ROOT"],
          !rootPath.isEmpty else {
        return
    }

    let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
    if ProcessInfo.processInfo.environment["COCOASPICE_SCAN_PERSIST"] == "1" {
        let database = try LibraryDatabase()
        try database.addRoot(path: rootURL.path)
        guard let root = try database.loadRoots().first(where: { $0.standardizedURL == rootURL.standardizedFileURL }) else {
            Issue.record("Could not load persisted scan root")
            return
        }
        let summary = try await LibraryScanCoordinator(database: database).run(root: root, mode: .newScan) { status in
            FileHandle.standardOutput.write(Data("\(status)\n".utf8))
        }
        FileHandle.standardOutput.write(Data("completed=\(summary.completed) successful=\(summary.successful) failed=\(summary.failed) unsupported=\(summary.unsupported)\n".utf8))
        for failure in summary.failures {
            let entry = failure.identity.archiveEntry.map { "#\($0)" } ?? ""
            FileHandle.standardOutput.write(Data("failure [\(failure.stage.rawValue)] \(failure.identity.path)\(entry): \(failure.message)\n".utf8))
        }
        return
    }
    let candidates = await ScanFilesystemDiscovery.discover(
        rootID: 1,
        rootURL: rootURL,
        registry: ScanCoreHandlers.registry
    )
    FileHandle.standardOutput.write(Data("discovered \(candidates.count) candidates\n".utf8))

    let accumulator = try await ScanPipelineExecutor().process(
        plan: ScanPlan(mode: .newScan, candidates: candidates),
        progress: { current, total, detail in
            FileHandle.standardOutput.write(Data("[\(current)/\(total)] \(detail)\n".utf8))
        },
        persist: { _ in }
    )
    let summary = await accumulator.summary
    FileHandle.standardOutput.write(Data("completed=\(summary.completed) successful=\(summary.successful) failed=\(summary.failed) unsupported=\(summary.unsupported)\n".utf8))
    for failure in summary.failures {
        let entry = failure.identity.archiveEntry.map { "#\($0)" } ?? ""
        FileHandle.standardOutput.write(Data("failure [\(failure.stage.rawValue)] \(failure.identity.path)\(entry): \(failure.message)\n".utf8))
    }
    #expect(summary.completed >= candidates.count)
}

@Test func scanResultAccumulatorLogsFailuresButOnlyTalliesSuccesses() async throws {
    let fingerprint = ScanFingerprint(fileSize: 1, modifiedAt: Date(timeIntervalSince1970: 1))
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: "/music/song.gbs", archiveEntry: nil),
        fingerprint: fingerprint,
        sourceURL: URL(fileURLWithPath: "/music/song.gbs"),
        route: nil
    )
    let accumulator = ScanResultAccumulator(discovered: 3)
    try await accumulator.accept(.success(
        candidate,
        ScanInspection(route: ScanRoute(pluginID: "gme", formatExtension: "gbs", supportsArchiveMembers: true, supportsMultiTrack: true), tracks: [])
    ))
    try await accumulator.accept(.unsupported(candidate))
    try await accumulator.accept(.failure(ScanFailure(
        identity: candidate.identity,
        fingerprint: candidate.fingerprint,
        route: candidate.route,
        stage: .metadata,
        message: "bad metadata"
    )))

    let summary = await accumulator.summary
    #expect(summary.discovered == 3)
    #expect(summary.completed == 3)
    #expect(summary.successful == 1)
    #expect(summary.unsupported == 1)
    #expect(summary.failed == 1)
    #expect(summary.failures.count == 1)
}

private enum CocoaSpiceTestError: Error {
    case expected
}

@Test func scanDiscoveryWalksNestedSupportedFilesAndArchives() async throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let nestedURL = rootURL.appendingPathComponent("a/b/c", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    try Data("spc".utf8).write(to: nestedURL.appendingPathComponent("track.spc"))
    try Data("archive".utf8).write(to: rootURL.appendingPathComponent("set.7z"))
    try Data("ignored".utf8).write(to: nestedURL.appendingPathComponent("notes.txt"))

    let result = await ScanFilesystemDiscovery.discover(
        rootID: 1,
        rootURL: rootURL,
        registry: ScanCoreHandlers.registry
    )
    #expect(result.map { URL(fileURLWithPath: $0.identity.path).lastPathComponent } == ["track.spc", "set.7z"])
}

@Test func gbsInspectionExposesAllTracks() async throws {
    let sampleURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/NSF/NSF/Development/GBS Rips/Metroid II - Return of Samus.gbs")
    guard FileManager.default.fileExists(atPath: sampleURL.path) else { return }

    let tracks = try await PlaybackInspection.inspectPlayableTracks(fileURL: sampleURL)
    #expect(tracks.count == 19)
    #expect(tracks.first?.track.trackIndex == 0)
    #expect(tracks.last?.track.trackIndex == 18)
    #expect(tracks.allSatisfy { $0.track.trackCount == 19 })
}

@Test func kssInspectionExposesAllTracks() async throws {
    let sampleURL = URL(fileURLWithPath: "/tmp/cocoaspice-kss-probe/T-81087.kss")
    guard FileManager.default.fileExists(atPath: sampleURL.path) else { return }

    let tracks = try await PlaybackInspection.inspectPlayableTracks(fileURL: sampleURL)
    #expect(tracks.count == 256)
    #expect(tracks.first?.track.trackIndex == 0)
    #expect(tracks.last?.track.trackIndex == 255)
    #expect(tracks.allSatisfy { $0.track.trackCount == 256 })
}

@Test @MainActor func spectrumAnalyzerUsesFortyBands() {
    #expect(ToolbarSpectrumModel.bandCount == 40)
}

@Test func playbackBackendRoutesVGMFamilyToLibVGM() {
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "spc") == .gme)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "nsf") == .gme)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "vgm") == .libvgm)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "vgz") == .libvgm)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "gym") == .libvgm)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "s98") == .libvgm)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "gsf") == .highlyComplete)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "minigsf") == .highlyComplete)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "usf") == .lazyUSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "miniusf") == .lazyUSF)
}

@Test func frameAccountingUsesSuppliedOutputFrames() {
    #expect(PlaybackFrameAccounting.positionFrames(
        sessionStartFrame: 44_100,
        framesSupplied: 22_050
    ) == 66_150)
    #expect(PlaybackFrameAccounting.positionSeconds(
        sessionStartFrame: 44_100,
        framesSupplied: 22_050,
        sampleRate: 44_100
    ) == 1.5)
}

@Test func frameAccountingDoesNotMoveBackwardsForNegativeSupply() {
    #expect(PlaybackFrameAccounting.positionFrames(
        sessionStartFrame: 44_100,
        framesSupplied: -1
    ) == 44_100)
}

@Test func nativeCompletionWaitsForBufferedFramesToDrain() {
    #expect(!PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: true,
        plannedFrameCount: nil,
        framesSupplied: 10_000,
        bufferedFrames: 512
    ))
    #expect(PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: true,
        plannedFrameCount: nil,
        framesSupplied: 10_000,
        bufferedFrames: 0
    ))
}

@Test func fixedDurationCompletionUsesPlannedFramesAndDrain() {
    #expect(!PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: false,
        plannedFrameCount: 44_100,
        framesSupplied: 44_100,
        bufferedFrames: 256
    ))
    #expect(PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: false,
        plannedFrameCount: 44_100,
        framesSupplied: 44_100,
        bufferedFrames: 0
    ))
    #expect(!PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: false,
        plannedFrameCount: 44_100,
        framesSupplied: 44_099,
        bufferedFrames: 0
    ))
}

@Test func realtimeRingBufferPreservesStereoFramesAndCapacity() throws {
    let ringBuffer = try RealtimePCMFrameRingBuffer(capacityFrames: 3)
    let inputLeft: [Float] = [0.1, 0.2, 0.3, 0.4]
    let inputRight: [Float] = [1.1, 1.2, 1.3, 1.4]

    let written = inputLeft.withUnsafeBufferPointer { left in
        inputRight.withUnsafeBufferPointer { right in
            ringBuffer.write(left: left, right: right)
        }
    }

    #expect(written == 3)
    #expect(ringBuffer.bufferedFrames == 3)

    var outputLeft = Array(repeating: Float.zero, count: 3)
    var outputRight = Array(repeating: Float.zero, count: 3)
    let read = outputLeft.withUnsafeMutableBufferPointer { left in
        outputRight.withUnsafeMutableBufferPointer { right in
            ringBuffer.read(left: left, right: right)
        }
    }

    #expect(read == 3)
    #expect(outputLeft == [0.1, 0.2, 0.3])
    #expect(outputRight == [1.1, 1.2, 1.3])
    #expect(ringBuffer.bufferedFrames == 0)
}

@Test func realtimeRingBufferWrapsAfterReadAndClear() throws {
    let ringBuffer = try RealtimePCMFrameRingBuffer(capacityFrames: 3)
    let firstLeft: [Float] = [1, 2]
    let firstRight: [Float] = [11, 12]
    _ = firstLeft.withUnsafeBufferPointer { left in
        firstRight.withUnsafeBufferPointer { right in
            ringBuffer.write(left: left, right: right)
        }
    }

    var discardedLeft = Array(repeating: Float.zero, count: 2)
    var discardedRight = Array(repeating: Float.zero, count: 2)
    _ = discardedLeft.withUnsafeMutableBufferPointer { left in
        discardedRight.withUnsafeMutableBufferPointer { right in
            ringBuffer.read(left: left, right: right)
        }
    }

    let secondLeft: [Float] = [3, 4, 5]
    let secondRight: [Float] = [13, 14, 15]
    _ = secondLeft.withUnsafeBufferPointer { left in
        secondRight.withUnsafeBufferPointer { right in
            ringBuffer.write(left: left, right: right)
        }
    }

    var outputLeft = Array(repeating: Float.zero, count: 3)
    var outputRight = Array(repeating: Float.zero, count: 3)
    _ = outputLeft.withUnsafeMutableBufferPointer { left in
        outputRight.withUnsafeMutableBufferPointer { right in
            ringBuffer.read(left: left, right: right)
        }
    }

    #expect(outputLeft == [3, 4, 5])
    #expect(outputRight == [13, 14, 15])

    ringBuffer.clear()
    #expect(ringBuffer.bufferedFrames == 0)
    #expect(ringBuffer.framesRead == 0)
    #expect(ringBuffer.framesRequested == 0)
    #expect(ringBuffer.underrunCount == 0)
}

@Test func realtimeRingBufferTracksOutputDemandAndUnderruns() throws {
    let ringBuffer = try RealtimePCMFrameRingBuffer(capacityFrames: 2)
    let input: [Float] = [1, 2]
    _ = input.withUnsafeBufferPointer { values in
        ringBuffer.write(left: values, right: values)
    }

    var outputLeft = Array(repeating: Float.zero, count: 3)
    var outputRight = Array(repeating: Float.zero, count: 3)
    _ = outputLeft.withUnsafeMutableBufferPointer { left in
        outputRight.withUnsafeMutableBufferPointer { right in
            ringBuffer.read(left: left, right: right)
        }
    }

    #expect(ringBuffer.framesRequested == 3)
    #expect(ringBuffer.framesRead == 2)
    #expect(ringBuffer.underrunCount == 1)
}

@Test func rapidQueueNavigationCanAdvanceFromPendingTrack() {
    let first = TrackItem(url: URL(fileURLWithPath: "/tmp/one.spc"))
    let second = TrackItem(url: URL(fileURLWithPath: "/tmp/two.spc"))
    let third = TrackItem(url: URL(fileURLWithPath: "/tmp/three.spc"))
    let playlist = [first, second, third]

    let nextFromFirst = QueueTransportNavigation.adjacentTrack(
        from: first,
        in: playlist,
        direction: .next,
        wraps: true
    )
    let nextFromPending = QueueTransportNavigation.adjacentTrack(
        from: nextFromFirst,
        in: playlist,
        direction: .next,
        wraps: true
    )

    #expect(nextFromFirst == second)
    #expect(nextFromPending == third)
}

@Test func databaseSidebarDisambiguatesDuplicateGameTitlesBySystem() {
    let items = DatabaseSidebarPresentation.disambiguateGameItems([
        DatabaseGameItem(name: "Mega Man", systemName: "NES", trackCount: 10),
        DatabaseGameItem(name: "Mega Man", systemName: "Game Boy", trackCount: 12),
        DatabaseGameItem(name: "Actraiser", systemName: "SNES", trackCount: 18)
    ])

    #expect(items[0].id != items[1].id)
    #expect(items[0].displayName == "Mega Man (NES)")
    #expect(items[1].displayName == "Mega Man (Game Boy)")
    #expect(items[2].displayName == "Actraiser")
    #expect(items[0].searchableName.contains("nes"))
}

@MainActor
@Test func databaseSidebarSearchPreservesSelection() {
    let sidebar = DatabaseSidebarState()
    let selected = DatabaseGameItem(name: "Actraiser", systemName: "SNES", trackCount: 18)
    let other = DatabaseGameItem(name: "Mega Man", systemName: "NES", trackCount: 10)
    sidebar.replaceGameItems([selected, other])
    sidebar.selectedGameID = selected.id
    sidebar.selectedGameIDs = [selected.id]

    sidebar.searchText = "Mega"

    #expect(sidebar.visibleGameItems == [other])
    #expect(sidebar.selectedGameID == selected.id)
    #expect(sidebar.selectedGameIDs == [selected.id])
}

@MainActor
@Test func databaseSidebarReloadDropsRemovedSelection() {
    let sidebar = DatabaseSidebarState()
    let selected = DatabaseGameItem(name: "Actraiser", systemName: "SNES", trackCount: 18)
    let remaining = DatabaseGameItem(name: "Mega Man", systemName: "NES", trackCount: 10)
    sidebar.replaceGameItems([selected, remaining])
    sidebar.selectedGameID = selected.id
    sidebar.selectedGameIDs = [selected.id]

    sidebar.replaceGameItems([remaining])

    #expect(sidebar.selectedGameID == nil)
    #expect(sidebar.selectedGameIDs.isEmpty)
}

@Test func persistedTrackIdentityRoundTripsMultiTrackLeaf() {
    let original = TrackItem(
        url: URL(fileURLWithPath: "/tmp/test.nsf"),
        trackIndex: 3,
        trackCount: 12
    )
    let restored = TrackItem.fromPersistedValue(original.persistedValue)
    #expect(restored == original)
}

@Test func persistedTrackIdentityRoundTripsArchiveLeaf() {
    let original = TrackItem(
        archiveURL: URL(fileURLWithPath: "/tmp/archive.zip"),
        entryPath: "Nintendo/Music/test.nsf",
        trackIndex: 2,
        trackCount: 8
    )
    let restored = TrackItem.fromPersistedValue(original.persistedValue)
    #expect(restored == original)
}

@Test func playlistM3URoundTripsArchiveLeaf() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let archiveURL = temporaryDirectory.appendingPathComponent("Library.zip")
    try Data().write(to: archiveURL)

    let original = TrackItem(
        archiveURL: archiveURL,
        entryPath: "Game Folder/song.nsf",
        trackIndex: 1,
        trackCount: 4
    )

    let encoded = PlaylistM3UCodec.encode([original])
    let decoded = PlaylistM3UCodec.decode(
        encoded,
        baseDirectory: temporaryDirectory,
        supportedExtensions: SPCFileScanner.supportedExtensions
    )

    #expect(decoded == [original])
}

@Test func droppedZipImportCreatesArchiveTracks() async throws {
    #expect(FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"))

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let playableURL = temporaryDirectory.appendingPathComponent("test.spc")
    try Data("not-a-real-spc".utf8).write(to: playableURL)
    let ignoredURL = temporaryDirectory.appendingPathComponent("ignored.txt")
    try Data("ignore".utf8).write(to: ignoredURL)
    let archiveURL = temporaryDirectory.appendingPathComponent("Drop.zip")

    try runProcess(
        executable: "/usr/bin/zip",
        arguments: ["-q", archiveURL.path, playableURL.lastPathComponent, ignoredURL.lastPathComponent],
        workingDirectory: temporaryDirectory
    )

    let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [archiveURL])
    #expect(loaded.tracks.count == 1)
    #expect(loaded.tracks[0].isArchiveEntry)
    #expect(loaded.tracks[0].url == archiveURL.standardizedFileURL)
    #expect(loaded.tracks[0].archiveEntryPath == "test.spc")

    let extractedURL = try ZipArchiveSupport.materializePlayableFile(for: loaded.tracks[0])
    let extractedData = try Data(contentsOf: extractedURL)
    #expect(extractedData == Data("not-a-real-spc".utf8))
}

@Test func droppedSevenZipImportCreatesArchiveTracks() async throws {
    let sevenZipPath = "/opt/homebrew/bin/7zz"
    guard FileManager.default.isExecutableFile(atPath: sevenZipPath) else { return }

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let playableURL = temporaryDirectory.appendingPathComponent("test.spc")
    try Data("not-a-real-spc".utf8).write(to: playableURL)
    let archiveURL = temporaryDirectory.appendingPathComponent("Drop.7z")

    try runProcess(
        executable: sevenZipPath,
        arguments: ["a", "-bd", "-y", archiveURL.path, playableURL.lastPathComponent],
        workingDirectory: temporaryDirectory
    )

    let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [archiveURL])
    #expect(loaded.tracks.count == 1)
    #expect(loaded.tracks[0].isArchiveEntry)
    #expect(loaded.tracks[0].archiveEntryPath == "test.spc")

    let extractedURL = try ZipArchiveSupport.materializePlayableFile(for: loaded.tracks[0])
    #expect(try Data(contentsOf: extractedURL) == Data("not-a-real-spc".utf8))
}

@Test func folderQueueIncludesArchiveMembers() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let playableURL = temporaryDirectory.appendingPathComponent("folder-track.spc")
    try Data("not-a-real-spc".utf8).write(to: playableURL)
    let archiveURL = temporaryDirectory.appendingPathComponent("Folder.zip")
    try runProcess(
        executable: "/usr/bin/zip",
        arguments: ["-q", archiveURL.path, playableURL.lastPathComponent],
        workingDirectory: temporaryDirectory
    )
    try FileManager.default.removeItem(at: playableURL)

    let tracks = await PlaylistQueueLoader.loadTracks(in: temporaryDirectory)
    #expect(tracks.count == 1)
    #expect(tracks[0].isArchiveEntry)
    #expect(tracks[0].archiveEntryPath == "folder-track.spc")
}

@Test func droppedMiniGSFImportFallsBackWithoutCrashing() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let miniGSFURL = temporaryDirectory.appendingPathComponent("test.minigsf")
    try Data("not-a-real-minigsf".utf8).write(to: miniGSFURL)

    let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [miniGSFURL])
    #expect(loaded.tracks.count == 1)
    #expect(loaded.tracks[0].url == miniGSFURL.standardizedFileURL)
    #expect(loaded.metadata.isEmpty)
}

@Test func droppedM3UImportAppendsDecodedTracks() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let trackURL = temporaryDirectory.appendingPathComponent("track.spc")
    try Data("not-a-real-spc".utf8).write(to: trackURL)
    let playlistURL = temporaryDirectory.appendingPathComponent("queue.m3u")
    try "#EXTM3U\ntrack.spc\n".write(to: playlistURL, atomically: true, encoding: .utf8)

    let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [playlistURL])

    #expect(loaded.tracks == [TrackItem(url: trackURL)])
}

@MainActor
@Test func longPlaySupportsAnyCurrentPlayableFormat() {
    let model = PlayerViewModel()
    model.currentTrack = TrackItem(url: URL(fileURLWithPath: "/tmp/test.nsf"))
    #expect(model.currentTrackSupportsLongPlay)
}

@Test func playbackPlanHasOnlyDefaultAndLongPlayModes() {
    let metadata = TrackMetadata(
        game: "",
        song: "",
        system: "",
        author: "",
        comment: "",
        introLengthMs: 1_000,
        loopLengthMs: 2_000,
        playLengthMs: 0,
        fadeLengthMs: 0
    )

    let vgmPlan = PlaybackTimingPolicy.playbackPlan(
        metadata: metadata,
        trackPathExtension: "vgz",
        longPlayEnabled: false,
        manualPreFadeSeconds: 240,
        fadeSeconds: 6
    )
    #expect(!vgmPlan.usesNativeEnding)
    #expect(vgmPlan.preFadeSeconds == 3)
    #expect(vgmPlan.totalSeconds == 9)

    let nsfPlan = PlaybackTimingPolicy.playbackPlan(
        metadata: metadata,
        trackPathExtension: "nsf",
        longPlayEnabled: true,
        manualPreFadeSeconds: 240,
        fadeSeconds: 6
    )
    #expect(!nsfPlan.usesNativeEnding)
    #expect(nsfPlan.preFadeSeconds == 240)
}

@Test func playbackPreferencesRestoreOnlyUnifiedKeys() {
    let suiteName = "CocoaSpiceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create isolated UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(true, forKey: "CocoaSpice.generalLongPlayEnabled")
    defaults.set(321, forKey: "CocoaSpice.generalManualPreFadeSeconds")

    let legacyOnlyPreferences = AppSessionPersistence.restorePlaybackPreferences(defaults: defaults)
    #expect(!legacyOnlyPreferences.longPlayEnabled)
    #expect(legacyOnlyPreferences.manualPreFadeSeconds == nil)
    #expect(!legacyOnlyPreferences.databaseSidebarMonospaceFont)
    #expect(!legacyOnlyPreferences.sidebarSystemMode)

    defaults.set(true, forKey: AppDefaultsKey.longPlayEnabled)
    defaults.set(240, forKey: AppDefaultsKey.manualPreFadeSeconds)
    defaults.set("0.100000,0.200000,0.300000,1.000000", forKey: AppDefaultsKey.spectrumGradientStartColor)
    defaults.set("0.900000,0.800000,0.700000,1.000000", forKey: AppDefaultsKey.spectrumGradientEndColor)
    defaults.set("0.400000,0.500000,0.600000,1.000000", forKey: AppDefaultsKey.spectrumPeakColor)
    defaults.set(true, forKey: AppDefaultsKey.sidebarSystemMode)
    defaults.set(true, forKey: AppDefaultsKey.databaseSidebarMonospaceFont)

    let unifiedPreferences = AppSessionPersistence.restorePlaybackPreferences(defaults: defaults)
    #expect(unifiedPreferences.longPlayEnabled)
    #expect(unifiedPreferences.manualPreFadeSeconds == 240)
    #expect(unifiedPreferences.spectrumGradientStartColor == "0.100000,0.200000,0.300000,1.000000")
    #expect(unifiedPreferences.spectrumGradientEndColor == "0.900000,0.800000,0.700000,1.000000")
    #expect(unifiedPreferences.spectrumPeakColor == "0.400000,0.500000,0.600000,1.000000")
    #expect(unifiedPreferences.databaseSidebarMonospaceFont)
    #expect(unifiedPreferences.sidebarSystemMode)
}

@Test func legacyPreferencesMigrateToCocoaSpiceKeys() {
    let suiteName = "CocoaSpiceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create isolated UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set("/tmp/music", forKey: "SPCBoy.lastRootPath")
    defaults.set(true, forKey: "SPCBoy.longPlayEnabled")
    defaults.set("already-current", forKey: AppDefaultsKey.lastRootPath)

    AppSessionPersistence.migrateLegacyPreferences(defaults: defaults)

    #expect(defaults.string(forKey: AppDefaultsKey.lastRootPath) == "already-current")
    #expect(defaults.bool(forKey: AppDefaultsKey.longPlayEnabled))
}

@Test func spectrumColorSerializationRoundTrips() {
    let color = NSColor(
        red: 0.25,
        green: 0.5,
        blue: 0.75,
        alpha: 1
    )
    let serialized = AppSessionPersistence.serializedColor(color)
    let restored = serialized.flatMap(AppSessionPersistence.deserializeColor)

    #expect(serialized == "0.250000,0.500000,0.750000,1.000000")
    #expect(restored?.redComponent == color.redComponent)
    #expect(restored?.greenComponent == color.greenComponent)
    #expect(restored?.blueComponent == color.blueComponent)
    #expect(restored?.alphaComponent == color.alphaComponent)
}

private func runProcess(
    executable: String,
    arguments: [String],
    workingDirectory: URL
) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory

    let stderr = Pipe()
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw TestProcessError.failed(errorText)
    }
}

private enum TestProcessError: Error {
    case failed(String)
}
