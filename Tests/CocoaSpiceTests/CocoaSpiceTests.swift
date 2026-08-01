import AppKit
import C2SF
import Foundation
import Testing
@testable import CocoaSpice

// Retain historic test names while production code uses the neutral registry.
private typealias GMEFormatSupport = PlaybackFormatRegistry

@MainActor
@Test func libraryScanRequestQueuePreservesFIFOOrderAndRootIdentity() {
    let firstRoot = LibraryScanRoot(
        id: 11,
        path: "/Music/First",
        isEnabled: true,
        displayOrder: 0,
        lastScanStartedAt: nil,
        lastScanCompletedAt: nil,
        lastScanTrackCount: 0,
        lastScanError: nil
    )
    let secondRoot = LibraryScanRoot(
        id: 22,
        path: "/Music/Second",
        isEnabled: true,
        displayOrder: 1,
        lastScanStartedAt: nil,
        lastScanCompletedAt: nil,
        lastScanTrackCount: 0,
        lastScanError: nil
    )
    let queue = LibraryScanRequestQueue()

    queue.enqueue(roots: [secondRoot, firstRoot], mode: .newScan)
    queue.enqueue(roots: [firstRoot], mode: .incremental)

    #expect(queue.count == 2)
    let firstRequest = queue.dequeue()
    #expect(firstRequest?.rootIDs == [22, 11])
    #expect(firstRequest?.mode == .newScan)
    let secondRequest = queue.dequeue()
    #expect(secondRequest?.rootIDs == [11])
    #expect(secondRequest?.mode == .incremental)
    #expect(queue.count == 0)
}

@MainActor
@Test func libraryOperationTaskStateInvalidatesFinishedAndCancelledWork() {
    let state = LibraryOperationsState()
    let firstGeneration = state.beginTask()
    #expect(state.isCurrentTask(firstGeneration))

    state.finishTask(generation: firstGeneration)
    #expect(!state.isCurrentTask(firstGeneration))

    let secondGeneration = state.beginTask()
    #expect(state.isCurrentTask(secondGeneration))
    state.cancelActiveTask()
    #expect(!state.isCurrentTask(secondGeneration))
}

@MainActor
@Test func latestTaskOwnerCancelsReplacedAndCompletedWork() {
    let owner = LatestTaskOwner()
    let firstGeneration = owner.begin()
    #expect(owner.isActive)
    let task = Task { @MainActor in
        await Task.yield()
    }
    owner.install(task, generation: firstGeneration)

    let secondGeneration = owner.begin()
    #expect(task.isCancelled)
    #expect(!owner.isCurrent(firstGeneration))
    #expect(owner.isCurrent(secondGeneration))

    owner.finish(generation: secondGeneration)
    #expect(!owner.isCurrent(secondGeneration))
    #expect(!owner.isActive)
}

@MainActor
@Test func playbackRequestStateInvalidatesCancelledRequestsAndTracksPendingPlayback() {
    let state = PlaybackRequestState()
    let track = TrackItem(url: URL(fileURLWithPath: "/tmp/theme.spc"))
    let generation = state.begin(track: track)

    #expect(state.pendingTrack == track)
    #expect(state.isCurrent(generation))
    state.cancel()
    #expect(state.pendingTrack == nil)
    #expect(!state.isCurrent(generation))
}

@MainActor
@Test func libraryOperationStateClampsScanProgressAndPrefersLinkTests() {
    let state = LibraryOperationsState()

    state.setScanProgress(rootID: 1, current: 120, total: 100)
    #expect(state.scanProgressByRootID[1] == LibraryScanProgress(current: 100, total: 100))
    #expect(state.operationProgress == LibraryScanProgress(current: 100, total: 100))

    state.linkTestProgress = LibraryScanProgress(current: 4, total: 9)
    #expect(state.operationProgress == LibraryScanProgress(current: 4, total: 9))

    state.clearScanProgress(rootID: 1)
    #expect(state.scanProgressByRootID.isEmpty)
    state.resetScanProgress()
    #expect(state.scanProgressByRootID.isEmpty)
}

@Test func databaseFileFolderDisclosureIgnoresRangeSelectionModifiers() {
    #expect(DatabaseFileSidebarInteraction.allowsFolderDisclosure(modifierFlags: []))
    #expect(!DatabaseFileSidebarInteraction.allowsFolderDisclosure(modifierFlags: .shift))
    #expect(!DatabaseFileSidebarInteraction.allowsFolderDisclosure(modifierFlags: .command))
    #expect(!DatabaseFileSidebarInteraction.allowsFolderDisclosure(modifierFlags: [.shift, .command]))
}

@MainActor
@Test func randomPlaybackScopesUseNativeSystemSymbols() {
    for scope in PlayerViewModel.RandomPlaybackScope.allCases {
        #expect(NSImage(systemSymbolName: scope.iconName, accessibilityDescription: nil) != nil)
    }
}

@Test func audioExportProgressReportsConcreteRemainingFileCount() {
    let snapshot = AudioExportProgressSnapshot(
        phase: .exporting,
        title: "Exporting AAC Audio",
        outputDirectoryPath: "/tmp",
        currentFileName: "Track.m4a",
        completedFiles: 3,
        totalFiles: 10,
        currentFileProgress: 0.5,
        batchProgress: 0.35
    )

    #expect(snapshot.remainingFiles == 7)
}

@Test func appVolumeIsBoundedToStockOutputRangeAndRestored() {
    #expect(AudioOutputVolume.clamped(-0.1) == 0)
    #expect(AudioOutputVolume.clamped(0.36) == 0.36)
    #expect(AudioOutputVolume.clamped(1.1) == 1)

    let suiteName = "CocoaSpiceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create isolated UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(0.36, forKey: AppDefaultsKey.appVolume)

    #expect(AppSessionPersistence.restorePlaybackPreferences(defaults: defaults).appVolume == 0.36)
}

@Test func wwiseEventBanksAreExcludedAsNonPlayableResources() throws {
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("bnk")
    try Data("BKHD\u{0}\u{0}\u{0}\u{0}".utf8).write(to: temporaryURL)
    defer { try? FileManager.default.removeItem(at: temporaryURL) }

    #expect(WwiseBankDetector.isEventBank(temporaryURL))
    #expect(!WwiseBankDetector.isEventBank(temporaryURL.deletingPathExtension().appendingPathExtension("fsb")))
}

@Test func ringBufferCountsOverScaleSamplesWithoutMutatingPCM() throws {
    let ringBuffer = try RealtimePCMFrameRingBuffer(capacityFrames: 8)
    let left: [Float] = [0.5, 1.1, -1.2]
    let right: [Float] = [-1.01, 0.25, 1.0]

    let written = left.withUnsafeBufferPointer { leftPointer in
        right.withUnsafeBufferPointer { rightPointer in
            ringBuffer.write(left: leftPointer, right: rightPointer)
        }
    }

    #expect(written == 3)
    #expect(ringBuffer.clippedSampleCount == 3)
    ringBuffer.clear()
    #expect(ringBuffer.clippedSampleCount == 0)
}

@Test func playbackDiagnosticsExpressesRingBufferHeadroom() {
    let diagnostics = PlaybackDiagnosticsSnapshot(
        bufferedFrames: 22_050,
        ringBufferFrames: 88_200,
        underrunCount: 2,
        clippedSampleCount: 3,
        sampleRate: 44_100,
        outputHealth: .running
    )

    #expect(diagnostics.bufferedMilliseconds == 500)
    #expect(diagnostics.bufferPercent == 25)
    #expect(diagnostics.outputHealth == .running)
}

@Test func signed16PCMNormalizesItsLegalMinimumWithoutAFalseClip() {
    #expect(PCMFloatConversion.normalized(.min) == -1)
    #expect(PCMFloatConversion.normalized(.max) < 1)
}

@Test func outputHeartbeatReportsAStalledOutputWithoutPlaybackQueueAccess() {
    let heartbeat = PlaybackOutputHeartbeat()
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    heartbeat.reset(expectingRenderRequests: true, now: start)

    #expect(heartbeat.health(framesRequested: 512, now: start) == .running)
    #expect(heartbeat.health(framesRequested: 512, now: start.addingTimeInterval(1.9)) == .running)
    #expect(heartbeat.health(framesRequested: 512, now: start.addingTimeInterval(2)) == .stalled)

    heartbeat.reset(expectingRenderRequests: false, now: start)
    #expect(heartbeat.health(framesRequested: 512, now: start.addingTimeInterval(10)) == .inactive)
}

@Test func remoteTransportNowPlayingKeepsPlaybackStateIndependentFromTheModel() {
    let nowPlaying = RemoteTransportNowPlaying(
        title: "Theme",
        albumTitle: "Game",
        elapsedSeconds: 42,
        durationSeconds: 180,
        isPlaying: true
    )

    #expect(nowPlaying.title == "Theme")
    #expect(nowPlaying.albumTitle == "Game")
    #expect(nowPlaying.elapsedSeconds == 42)
    #expect(nowPlaying.durationSeconds == 180)
    #expect(nowPlaying.isPlaying)
}

@Test func linearResamplerKeepsPlayStationXAOnTheOutputClock() {
    let resampler = LinearStereoResampler(
        sourceSampleRate: 37_800,
        outputSampleRate: 44_100
    )
    let source = (0...3_780).map(Float.init)
    resampler.append(DecodedChunk(left: source, right: source, frameCount: source.count))

    let rendered = resampler.render(maximumFrames: 4_410, endOfInput: false)

    #expect(rendered.frameCount == 4_410)
    #expect(rendered.left[0] == 0)
    #expect(rendered.left[7] == 6)
    #expect(rendered.right[3_500] == 3_000)
}

@Test func playlistPathUsesFullFilesystemAndArchiveMemberProvenance() {
    let fileTrack = TrackItem(url: URL(fileURLWithPath: "/Music/SNES/Track.spc"))
    let archiveTrack = TrackItem(
        archiveURL: URL(fileURLWithPath: "/Music/SNES/Game.7z"),
        entryPath: "Sound/Track.spc",
        trackIndex: 1,
        trackCount: 2
    )

    #expect(fileTrack.fullPathText == "/Music/SNES/Track.spc")
    #expect(archiveTrack.fullPathText == "/Music/SNES/Game.7z#Sound/Track.spc [2]")
}

@MainActor
@Test func playlistColumnsAutomaticallySizeAfterRowsArrive() async throws {
    let model = PlayerViewModel()
    model.pendingPlaylistColumnOrder = []
    model.pendingPlaylistColumnVisibility = [:]
    model.pendingPlaylistColumnWidths = [:]
    let track = TrackItem(
        url: URL(fileURLWithPath: "/tmp/\(String(repeating: "Long Playlist Filename ", count: 8)).spc")
    )
    model.playlist = [track]
    model.selectedTrackID = track.id
    model.selectedTrackIDs = [track.id]

    let coordinator = PlaylistTableView.Coordinator(model: model)
    let tableView = NSTableView()
    tableView.delegate = coordinator
    tableView.dataSource = coordinator
    coordinator.attach(tableView: tableView)
    coordinator.installColumns()

    let fileColumn = try #require(tableView.tableColumns.first {
        $0.identifier.rawValue == "file"
    })
    let initialWidth = fileColumn.width
    #expect(tableView.selectedRow == 0)

    try await Task.sleep(for: .milliseconds(500))

    #expect(fileColumn.width > initialWidth)
    #expect(tableView.selectedRow == 0)
}

@Test func supportedExtensionsIncludeLinkedLibGMETypes() {
    #expect(SPCFileScanner.supportedExtensions.contains("ay"))
    #expect(SPCFileScanner.supportedExtensions.contains("gbs"))
    #expect(SPCFileScanner.supportedExtensions.contains("hes"))
    #expect(SPCFileScanner.supportedExtensions.contains("kss"))
    #expect(SPCFileScanner.supportedExtensions.contains("nsf"))
    #expect(SPCFileScanner.supportedExtensions.contains("nsfe"))
    #expect(SPCFileScanner.supportedExtensions.contains("sap"))
    #expect(SPCFileScanner.supportedExtensions.contains("spc"))
    #expect(SPCFileScanner.supportedExtensions.contains("xm"))
    #expect(SPCFileScanner.supportedExtensions.contains("vgm"))
    #expect(SPCFileScanner.supportedExtensions.contains("vgz"))
    #expect(SPCFileScanner.supportedExtensions.contains("gsf"))
    #expect(SPCFileScanner.supportedExtensions.contains("minigsf"))
    #expect(SPCFileScanner.supportedExtensions.contains("usf"))
    #expect(SPCFileScanner.supportedExtensions.contains("miniusf"))
    #expect(SPCFileScanner.supportedExtensions.contains("2sf"))
    #expect(SPCFileScanner.supportedExtensions.contains("mini2sf"))
    #expect(SPCFileScanner.supportedExtensions.contains("psf"))
    #expect(SPCFileScanner.supportedExtensions.contains("minipsf"))
    #expect(SPCFileScanner.supportedExtensions.contains("psf2"))
    #expect(SPCFileScanner.supportedExtensions.contains("minipsf2"))
    #expect(SPCFileScanner.supportedExtensions.contains("xa"))
    #expect(SPCFileScanner.supportedExtensions.contains("stream"))
    #expect(SPCFileScanner.supportedExtensions.contains("wav"))
    #expect(SPCFileScanner.supportedExtensions.contains("flac"))
    #expect(!SPCFileScanner.supportedExtensions.contains("psflib"))
    #expect(!SPCFileScanner.supportedExtensions.contains("nds"))
}

@Test func playbackFormatRegistryNormalizesAdmissionForEveryIntakeSurface() {
    #expect(PlaybackFormatRegistry.admits(pathExtension: ".VGM"))
    #expect(PlaybackFormatRegistry.admits(fileURL: URL(fileURLWithPath: "/tmp/track.MP3")))
    #expect(!PlaybackFormatRegistry.admits(pathExtension: "mus"))
    #expect(PlaybackFormatRegistry.module(forPathExtension: " .TXTP ")?.pluginID == "vgmstream-txtp")
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

@Test func twoSFReplacementReleasesThePreviousGlobalCoreFirst() {
    let fileURL = URL(fileURLWithPath: "/tmp/cocoaspice-2sf-repro/01 Prologue.mini2sf")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    TwoSFBridgeGate.withLock {
        var firstError: UnsafeMutablePointer<CChar>?
        var first = fileURL.path.withCString { twosf_player_create($0, 44_100, &firstError) }
        defer {
            if let first { twosf_player_destroy(first) }
            if let firstError { twosf_error_message_free(firstError) }
        }
        guard let existing = first else {
            Issue.record("Could not open local 2SF reproduction fixture")
            return
        }

        twosf_player_destroy(existing)
        first = nil
        var replacementError: UnsafeMutablePointer<CChar>?
        let replacement = fileURL.path.withCString { twosf_player_create($0, 44_100, &replacementError) }
        defer {
            if let replacement { twosf_player_destroy(replacement) }
            if let replacementError { twosf_error_message_free(replacementError) }
        }
        guard let replacement else {
            Issue.record("Could not reload local 2SF reproduction fixture")
            return
        }

        var samples = [Int16](repeating: 0, count: 2_048)
        var rendered: Int32 = 0
        #expect(twosf_player_render_s16(replacement, 1_024, &samples, &rendered, &replacementError) == 0)
        #expect(rendered > 0)
    }
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

@Test func tarZstandardArchivesListAndMaterializePlayableMembers() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/SNESMusicOrg Zstd/F-Zero.tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    #expect(ZipArchiveSupport.canHandle(archiveURL))
    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: ["spc"]
    )
    #expect(entries.count == 17)
    guard let firstEntry = entries.first else {
        Issue.record("Expected playable SPC members in TAR+Zstandard fixture")
        return
    }

    let materializedURL = try ZipArchiveSupport.materializeEntry(
        archiveURL: archiveURL,
        entryPath: firstEntry.entryPath
    )
    #expect(FileManager.default.fileExists(atPath: materializedURL.path))
    #expect((try Data(contentsOf: materializedURL)).count > 0)

    let selectedRoot = try ZipArchiveSupport.materializeEntries(
        at: archiveURL,
        entryPaths: entries.prefix(2).map(\.entryPath)
    )
    #expect(FileManager.default.fileExists(
        atPath: ZipArchiveSupport.archiveMemberURL(
            in: selectedRoot,
            entryPath: firstEntry.entryPath
        ).path
    ))

    let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
        at: archiveURL,
        entryPaths: entries.prefix(2).map(\.entryPath)
    )
    #expect(FileManager.default.fileExists(
        atPath: ZipArchiveSupport.archiveMemberURL(
            in: scanRoot,
            entryPath: firstEntry.entryPath
        ).path
    ))
    ZipArchiveSupport.discardScanMaterialization(at: scanRoot)
    #expect(!FileManager.default.fileExists(atPath: scanRoot.path))

    let completeRoot = try ZipArchiveSupport.materializeArchive(at: archiveURL)
    #expect(FileManager.default.fileExists(
        atPath: ZipArchiveSupport.archiveMemberURL(
            in: completeRoot,
            entryPath: firstEntry.entryPath
        ).path
    ))
}

@Test func tarZstandardSelectedExtractionAcceptsLeadingDotMemberPaths() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Sony PlayStation 3/Hard Corps - Uprising (2011-03-15)(Arc System Works)(Konami)[PS3].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let entry = try #require(ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: ["at3"]
    ).first { $0.entryPath == "./Sound/SND0.AT3" })
    let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
        at: archiveURL,
        entryPaths: [entry.entryPath]
    )
    defer { ZipArchiveSupport.discardScanMaterialization(at: scanRoot) }

    #expect(FileManager.default.fileExists(
        atPath: ZipArchiveSupport.archiveMemberURL(in: scanRoot, entryPath: entry.entryPath).path
    ))
}

@Test func hardCorpsArchiveDecodesAA3AndFSBBNKAssets() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Sony PlayStation 3/Hard Corps - Uprising (2011-03-15)(Arc System Works)(Konami)[PS3].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: GMEFormatSupport.supportedExtensions
    )
    let aa3 = try #require(entries.first { $0.entryPath == "./Sound/Opening_000001BD.aa3" })
    let bnk = try #require(entries.first { $0.entryPath == "./Sound/BGM_ps3.bnk" })
    let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
        at: archiveURL,
        entryPaths: [aa3.entryPath, bnk.entryPath]
    )
    defer { ZipArchiveSupport.discardScanMaterialization(at: scanRoot) }

    for entry in [aa3, bnk] {
        let fileURL = ZipArchiveSupport.archiveMemberURL(in: scanRoot, entryPath: entry.entryPath)
        let inspector = try VGMStreamFileInspector(fileURL: fileURL)
        #expect(inspector.trackCount > 0)
        let decoder = try VGMStreamDecoder(track: TrackItem(url: fileURL), sampleRate: 44_100)
        #expect(try decoder.decode(frameCount: 1_024).frameCount > 0)
    }
}

@Test func bTeamArchiveRawPCM22WAVsInspectAndDecode() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Nintendo DS/B Team - Metal Cartoon Squad (2009-02-20)(Most Wanted)(Virgin Play)[NDS].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: ["wav"]
    )
    let entryPaths = [
        "Action2_22.wav",
        "Congratulations_22.wav",
        "Main_Theme_2_22.wav",
        "Main_Theme_3_22.wav",
        "ObjCompl_22.wav"
    ]
    let rawPCMEntries = try entryPaths.map { entryPath in
        try #require(entries.first { $0.entryPath == entryPath })
    }
    let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
        at: archiveURL,
        entryPaths: rawPCMEntries.map(\.entryPath)
    )
    defer { ZipArchiveSupport.discardScanMaterialization(at: scanRoot) }

    for entry in rawPCMEntries {
        let fileURL = ZipArchiveSupport.archiveMemberURL(in: scanRoot, entryPath: entry.entryPath)
        #expect(NDSRawPCM22.isRecognized(fileURL))
        let inspector = try PlaybackDecoderFactory.makeInspector(fileURL: fileURL)
        let metadata = try inspector.metadata(trackIndex: 0)
        #expect(metadata.system == "Nintendo DS")
        #expect(metadata.playLengthMs > 0)
        let decoder = try PlaybackDecoderFactory.makeDecoder(track: TrackItem(url: fileURL), sampleRate: 44_100)
        let chunk = try decoder.decode(frameCount: 1_024)
        #expect(chunk.frameCount == 1_024)
    }
}

@Test func everyRegisteredFormatUsesSharedDropAndScanAdmission() {
    for extensionName in GMEFormatSupport.supportedExtensions {
        let fileURL = URL(fileURLWithPath: "/tmp/cocoaspice-admission.\(extensionName)")
        #expect(PlaylistQueueLoader.canImportDroppedURL(fileURL))
        #expect(ScanCoreHandlers.registry.route(for: extensionName) != nil)
    }
}

@Test func tarZstandardListingsRemainReliableInParallel() async throws {
    let rootURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain Zstd/GBS")
    let archives = [
        "Gex 3 - Deep Pocket Gecko (EMU).zophar.tar.zst",
        "Honkaku Hanafuda GB (EMU).zophar.tar.zst",
        "J.League Excite Stage Tactics (EMU).zophar.tar.zst",
        "Kirby's Star Stacker (EMU).zophar.tar.zst"
    ].map { rootURL.appendingPathComponent($0) }
    guard archives.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }

    let count = try await withThrowingTaskGroup(of: Int.self, returning: Int.self) { group in
        for archiveURL in archives {
            group.addTask {
                try ZipArchiveSupport.listPlayableEntries(
                    in: archiveURL,
                    supportedExtensions: ["gbs"]
                ).count
            }
        }
        var total = 0
        for try await entryCount in group {
            total += entryCount
        }
        return total
    }
    #expect(count > 0)
}

@Test func tarZstandardListingAcceptsOnlyZstdsExpectedBrokenPipeExit() {
    #expect(ZipArchiveSupport.isExpectedTarListingBrokenPipe(
        exitStatus: 70,
        terminationReason: .exit,
        stderr: "zstd: error 70 : Write error : cannot write block : Broken pipe"
    ))
    #expect(!ZipArchiveSupport.isExpectedTarListingBrokenPipe(
        exitStatus: 70,
        terminationReason: .exit,
        stderr: "zstd: error 70 : Write error : disk full"
    ))
    #expect(!ZipArchiveSupport.isExpectedTarListingBrokenPipe(
        exitStatus: 1,
        terminationReason: .exit,
        stderr: "zstd: error 70 : Write error : cannot write block : Broken pipe"
    ))
}

@Test func ps3ArchiveAudioDecodesThroughVGMStream() throws {
    let ps3Root = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW Zstd/PS3", isDirectory: true)
    let harmonyArchive = ps3Root.appendingPathComponent("Castlevania - Harmony of Despair [Akumajou Dracula - Harmony of Despair] [PSN](2011-09-27)(Konami)[PS3].tar.zst")
    let lordsArchive = ps3Root.appendingPathComponent("Castlevania - Lords of Shadow 2 (2014-02-25)(MercurySteam)(Konami)[PS3].tar.zst")
    guard FileManager.default.fileExists(atPath: harmonyArchive.path),
          FileManager.default.fileExists(atPath: lordsArchive.path) else { return }

    let fixtures: [(URL, String, String)] = [
        (harmonyArchive, "02_vampirekiller.msf", "PlayStation 3"),
        (lordsArchive, "SND0.AT3", "PlayStation 3 / PSP"),
        (lordsArchive, "0.0 menu.ogg", "Game Audio")
    ]
    for (archiveURL, entryPath, expectedSystem) in fixtures {
        let decoder = try VGMStreamDecoder(
            track: TrackItem(archiveURL: archiveURL, entryPath: entryPath),
            sampleRate: 44_100
        )
        let metadata = try decoder.metadata()
        let chunk = try decoder.decode(frameCount: 2_048)

        #expect(GMEFormatSupport.playbackBackend(forPathExtension: URL(fileURLWithPath: entryPath).pathExtension) == .vgmstream)
        #expect(metadata.system == expectedSystem)
        #expect(chunk.frameCount > 0)
        #expect(chunk.left.contains { abs($0) > 0.0001 })
    }
}

@Test func pspArchiveAudioDecodesThroughVGMStream() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW Zstd/PSP/Silent Hill - Origins [Silent Hill Zero] (2007-11-06)(Climax Group)(Konami)[PSP].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    for entryPath in ["DARKTOWN.at3", "MUSTITLE.RWS"] {
        let decoder = try VGMStreamDecoder(
            track: TrackItem(archiveURL: archiveURL, entryPath: entryPath),
            sampleRate: 44_100
        )
        let metadata = try decoder.metadata()
        let chunk = try decoder.decode(frameCount: 2_048)

        #expect(GMEFormatSupport.playbackBackend(forPathExtension: URL(fileURLWithPath: entryPath).pathExtension) == .vgmstream)
        #expect(metadata.system == (entryPath.hasSuffix(".at3") ? "PlayStation 3 / PSP" : "Game Audio"))
        #expect(chunk.frameCount > 0)
        #expect(chunk.left.contains { abs($0) > 0.0001 })
    }
}

@Test func reportedTarZstandardScannerFailuresListAndExtract() throws {
    let gameGearArchive = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain Zstd/GAMEGEAR/Batman Returns (EMU).zophar.tar.zst")
    let gbsArchive = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain Zstd/GBS/Chalvo 55 (EMU).zophar.tar.zst")
    guard FileManager.default.fileExists(atPath: gameGearArchive.path),
          FileManager.default.fileExists(atPath: gbsArchive.path) else {
        return
    }

    _ = try ZipArchiveSupport.listPlayableEntries(
        in: gameGearArchive,
        supportedExtensions: GMEFormatSupport.supportedExtensions
    )
    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: gbsArchive,
        supportedExtensions: ["gbs"]
    )
    let entry = try #require(entries.first { $0.entryPath == "DMG-A2SJ-JPN.gbs" })
    let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
        at: gbsArchive,
        entryPaths: [entry.entryPath]
    )
    defer { ZipArchiveSupport.discardScanMaterialization(at: scanRoot) }
    #expect(FileManager.default.fileExists(
        atPath: ZipArchiveSupport.archiveMemberURL(in: scanRoot, entryPath: entry.entryPath).path
    ))
}

@Test func tarZstandardSelectedExtractionTreatsMemberNamesLiterally() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain Zstd/MASTERSYSTEM/Great Baseball [Card] (EMU).zophar.tar.zst")
    let entryPath = "Great Baseball [Card] - 01 - Title Screen.vgm"
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
        at: archiveURL,
        entryPaths: [entryPath]
    )
    defer { ZipArchiveSupport.discardScanMaterialization(at: scanRoot) }
    #expect(FileManager.default.fileExists(
        atPath: ZipArchiveSupport.archiveMemberURL(in: scanRoot, entryPath: entryPath).path
    ))
}

@Test func tarZstandardSelectedExtractionRestoresBSDTarOctalPathBytes() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/NEC PC-98/d/Doukyusei (PC-98)(1992)(elf).tar.zst")
    let entryPath = "02_ŐXé\\302\\255ĽÓéş.s98"
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let listedPath = try #require(ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: ["s98"]
    ).first { $0.entryPath == entryPath }?.entryPath)

    let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
        at: archiveURL,
        entryPaths: [listedPath]
    )
    defer { ZipArchiveSupport.discardScanMaterialization(at: scanRoot) }
    #expect(FileManager.default.fileExists(
        atPath: ZipArchiveSupport.archiveMemberURL(in: scanRoot, entryPath: listedPath).path
    ))
    let playbackURL = try ZipArchiveSupport.materializeEntry(
        archiveURL: archiveURL,
        entryPath: listedPath
    )
    #expect(FileManager.default.fileExists(atPath: playbackURL.path))
}

@Test func tarZstandardSelectedExtractionPreservesLeadingSpacesInMemberNames() throws {
    let archives = [
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Nintendo SNES/Congo's Caper [Tatakae Genshijin 2 - Rookie no Bouken] (1992-12-18)(DE Act Team)(Data East)[SNES].tar.zst"),
            [" Back to a Monkey.spc", " Don't Give Up!.spc", " Monkey See, Monkey Do....spc"]
        ),
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Nintendo SNES/Rise of the Robots (1994-12-22)(Mirage)(Data Design)(Acclaim)[SNES].tar.zst"),
            [" Heartbeat.spc"]
        )
    ]

    for (archiveURL, entryPaths) in archives {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { continue }
        let entries = try ZipArchiveSupport.listPlayableEntries(in: archiveURL, supportedExtensions: ["spc"])
        #expect(entryPaths.allSatisfy { expected in entries.contains { $0.entryPath == expected } })
        let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
            at: archiveURL,
            entryPaths: entryPaths
        )
        defer { ZipArchiveSupport.discardScanMaterialization(at: scanRoot) }
        for entryPath in entryPaths {
            #expect(FileManager.default.fileExists(
                atPath: ZipArchiveSupport.archiveMemberURL(in: scanRoot, entryPath: entryPath).path
            ))
        }
    }
}

@Test func malformedSPCMetadataFallsBackToTheDecoderInspector() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Nintendo SNES/Wicked 18 [Devil's Course] (1993-03-05)(T&E)[SNES].tar.zst")
    let entryPath = "07 Hole in One!.spc"
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
    let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
        at: archiveURL,
        entryPaths: [entryPath]
    )
    defer { ZipArchiveSupport.discardScanMaterialization(at: scanRoot) }
    let fileURL = ZipArchiveSupport.archiveMemberURL(in: scanRoot, entryPath: entryPath)
    let route = try #require(ScanCoreHandlers.registry.route(for: "spc", archiveMember: true))
    let handler = try #require(ScanCoreHandlers.handlers.handler(for: route))

    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    #expect(inspection.tracks.count == 1)
    #expect(try #require(inspection.tracks.first?.metadata).system == "Super Nintendo")
}

@Test func corruptS98AndMiniGSFPayloadsReceiveExplicitScannerReasons() throws {
    let fixtures = [
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/NEC PC-98/0-9/100Yen Disk Vol. 5 (PC-88)(1988)(Onion).tar.zst"),
            "100yen5pcm.s98",
            "Corrupt S98 payload"
        ),
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Nintendo Game Boy Advance/Yuujou no Victory Goal - 4V4 Arashi Get the Goal!! (2001-11-15)(KCE Studios)(Konami)[GBA].tar.zst"),
            "15 BGM #15.minigsf",
            "Corrupt GSF payload"
        )
    ]

    for (archiveURL, entryPath, expectedReason) in fixtures {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { continue }
        let scanRoot = try ZipArchiveSupport.materializeEntriesForScan(
            at: archiveURL,
            entryPaths: [entryPath]
        )
        defer { ZipArchiveSupport.discardScanMaterialization(at: scanRoot) }
        let fileURL = ZipArchiveSupport.archiveMemberURL(in: scanRoot, entryPath: entryPath)
        #expect(CorruptAudioPayloadDetector.reason(for: fileURL)?.contains(expectedReason) == true)
    }
}

@Test func misnamedNintendoDSSWAVUsesVGMStream() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Nintendo DS/Fifi and the Flowertots (2009-09-17)(-)(GSP)[NDS].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
    let track = TrackItem(archiveURL: archiveURL, entryPath: "game_00_SND_Fifi__adpcm.wav")
    let decoder = try PlaybackDecoderFactory.makeDecoder(track: track, sampleRate: 44_100)
    let metadata = try decoder.metadata()
    let chunk = try decoder.decode(frameCount: 2_048)
    #expect(metadata.system == "Nintendo DS")
    #expect(chunk.frameCount > 0)
}

@Test func silentHillSequenceBanksAreRecognizedAsNonPlayableKDTData() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Sony PlayStation 3/Silent Hill HD Collection (2012-03-20)(Hijinx)(Konami)[PS3].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
    let rootURL = try ZipArchiveSupport.materializeArchiveForScan(at: archiveURL)
    defer { ZipArchiveSupport.discardScanMaterialization(at: rootURL) }
    #expect(KDTSequenceDetector.isSilentHillSequenceBank(rootURL.appendingPathComponent("sh3_bgm_01.hd")))
}

@Test func silentHillSequenceBanksDoNotPreventArchiveCompletion() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Sony PlayStation 3/Silent Hill HD Collection (2012-03-20)(Hijinx)(Konami)[PS3].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
    let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: archiveURL.path, archiveEntry: nil),
        fingerprint: ScanFingerprint(fileSize: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate ?? .distantPast),
        sourceURL: archiveURL,
        route: nil
    )
    let results = await ScanPipelineExecutor().process(candidate)
    #expect(results.contains { if case .unsupported = $0 { return true }; return false })
    #expect(results.contains { if case .archiveCompleted = $0 { return true }; return false })
    #expect(!results.contains { if case .failure = $0 { return true }; return false })
}


@Test func vgzMetadataReaderReadsProject2612GD3Tag() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/Project2612 Zstd/Twin Cobra (Kyuukyoku Tiger).tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let rootURL = try ZipArchiveSupport.materializeArchive(at: archiveURL)
    let fileURL = ZipArchiveSupport.archiveMemberURL(
        in: rootURL,
        entryPath: "01 - Challenge (Opening Theme) ~ Break a Leg! (BGM 1, 6).vgz"
    )
    guard let metadata = VGMMetadataReader.read(fileURL: fileURL) else {
        Issue.record("Expected direct GD3 metadata from Project2612 VGZ fixture")
        return
    }

    #expect(metadata.song == "Challenge (Opening Theme) ~ Break a Leg! (BGM 1, 6)")
    #expect(!metadata.game.isEmpty)
    #expect(metadata.playLengthMs > 0)
}

@Test func playPSFRecognizesStandalonePlayStationFixture() throws {
    let fileURL = URL(fileURLWithPath: "/private/tmp/cocoaspice-psx-fixtures/standalone/01 Title.psf")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    let inspector = try PlayPSFFileInspector(fileURL: fileURL)
    let metadata = try inspector.metadata(trackIndex: 0)
    #expect(metadata.system == "PlayStation")
    #expect(!metadata.song.isEmpty)
    #expect(metadata.playLengthMs == 64_000)
    #expect(metadata.fadeLengthMs == 10_000)
}

@Test func psfMetadataReaderReadsContainerFooterWithoutDecoder() throws {
    let fileURL = URL(fileURLWithPath: "/private/tmp/cocoaspice-psx-fixtures/standalone/01 Title.psf")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    let metadata = try PSFMetadataReader.read(fileURL: fileURL)
    #expect(metadata?.system == "PlayStation")
    #expect(metadata?.song.isEmpty == false)
    #expect(metadata?.playLengthMs == 64_000)
    #expect(metadata?.fadeLengthMs == 10_000)
}

@Test func playPSFLoadsSiblingPSFLibraries() throws {
    let fileURL = URL(fileURLWithPath: "/private/tmp/cocoaspice-psx-fixtures/dependent/01-BOBBY_A.psf")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    let decoder = try PlayPSFDecoder(track: TrackItem(url: fileURL), sampleRate: 44_100)
    let chunk = try decoder.decode(frameCount: 1_024)
    #expect(chunk.frameCount > 0)
    #expect(try decoder.metadata().system == "PlayStation")
    decoder.setSuspended(true)
    decoder.setSuspended(false)
    try decoder.seek(toMilliseconds: 0)
    #expect(try decoder.decode(frameCount: 1_024).frameCount > 0)
}

@Test func archivePSFLoadsItsSiblingLibrariesFromOneMaterializedSet() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain/PSF/Clock Tower - The First Fear (EMU).zophar.zip")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let decoder = try PlayPSFDecoder(
        track: TrackItem(archiveURL: archiveURL, entryPath: "01-BOBBY_A.psf"),
        sampleRate: 44_100
    )
    let chunk = try decoder.decode(frameCount: 1_024)
    #expect(chunk.frameCount > 0)
}

@Test func residentEvil2PSFArchiveProducesAudioAcrossBothLibraryLayouts() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain/PSF/resident-evil-2-[biohazard-2].psf.zip")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: ["psf"]
    )
    #expect(entries.contains { $0.entryPath.hasPrefix("UNKNOWN/") })

    for entry in entries where !entry.entryPath.contains("949 - Unknown (Won't play)") {
        let decoder = try PlayPSFDecoder(
            track: TrackItem(archiveURL: archiveURL, entryPath: entry.entryPath),
            sampleRate: 44_100
        )
        let chunks = try (0..<4).map { _ in try decoder.decode(frameCount: 2_048) }
        #expect(chunks.allSatisfy { $0.frameCount == 2_048 }, "\(entry.entryPath) stopped producing PCM")
    }
}

@Test func residentEvil2PSFTracksWaitForEmulatorStartup() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain/PSF/resident-evil-2-[biohazard-2].psf.zip")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    for entryPath in ["06 Prologue.psf", "UNKNOWN/901 - Unknown.psf"] {
        let decoder = try PlayPSFDecoder(
            track: TrackItem(archiveURL: archiveURL, entryPath: entryPath),
            sampleRate: 44_100
        )
        let chunks = try (0..<4).map { _ in try decoder.decode(frameCount: 2_048) }
        #expect(chunks.allSatisfy { $0.frameCount == 2_048 }, "\(entryPath) stopped producing PCM")
        if entryPath == "06 Prologue.psf" {
            #expect(chunks.contains { chunk in
                chunk.left.contains(where: { $0 != 0 }) || chunk.right.contains(where: { $0 != 0 })
            }, "\(entryPath) produced only silence")
        }
    }
}

@Test func vgmstreamRecognizesPlayStationXA() throws {
    let fileURL = URL(fileURLWithPath: "/private/tmp/cocoaspice-psx-fixtures/xa/SLUS-00772_01 - Keep Yourself Alive (Sol's Theme).XA")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    let decoder = try VGMStreamDecoder(
        track: TrackItem(url: fileURL),
        sampleRate: 44_100
    )
    let inspector = try VGMStreamFileInspector(fileURL: fileURL)
    #expect(inspector.trackCount >= 1)
    #expect(decoder.sampleRate == 37_800)
    let metadata = try inspector.metadata(trackIndex: 0)
    #expect(metadata.system == "PlayStation")
    #expect(metadata.playLengthMs > 0)
}

@Test func vgmstreamRecognizes3DOGENH() throws {
    let fileURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/3DO/TE/Total Eclipse (1993)(Crystal Dynamics)[3DO]/TEcredits.GENH")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    let decoder = try VGMStreamDecoder(track: TrackItem(url: fileURL), sampleRate: 44_100)
    let inspector = try VGMStreamFileInspector(fileURL: fileURL)
    #expect(inspector.trackCount == 1)
    #expect(decoder.sampleRate > 0)
    let metadata = try inspector.metadata(trackIndex: 0)
    #expect(metadata.system == "3DO")
    #expect(metadata.playLengthMs > 0)
    #expect(metadata.comment.contains("GENH"))
}

@Test func vgmstreamRecognizes3DONeuroDancerStream() throws {
    let fileURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/Derived/NeuroDancer - Journey into the Neuronet! (USA) [audio harvest]/extracted/jendance6.stream")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "STREAM") == .vgmstream)
    #expect(GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "stream"))
    #expect(ScanCoreHandlers.registry.route(for: "stream", archiveMember: false)?.pluginID == "vgmstream")
    #expect(PlaylistQueueLoader.canImportDroppedURL(fileURL))

    let inspector = try VGMStreamFileInspector(fileURL: fileURL)
    #expect(inspector.trackCount == 1)
    let metadata = try inspector.metadata(trackIndex: 0)
    #expect(metadata.system == "3DO")

    let decoder = try VGMStreamDecoder(track: TrackItem(url: fileURL), sampleRate: 44_100)
    let chunks = try (0..<4).map { _ in try decoder.decode(frameCount: 2_048) }
    #expect(chunks.allSatisfy { $0.frameCount == 2_048 })
    #expect(chunks.contains { chunk in
        chunk.left.contains(where: { $0 != 0 }) || chunk.right.contains(where: { $0 != 0 })
    })
}

@Test func joshWPCGrimoireFSBScansAndDecodesThroughVGMStream() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/PC/Castlevania - Grimoire of Souls (2021-09-17)(Konami)[macOS].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "fsb") == .vgmstream)
    #expect(ScanCoreHandlers.registry.route(for: "fsb", archiveMember: true)?.pluginID == "vgmstream")
    let entry = try #require(ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: SPCFileScanner.supportedExtensions
    ).first { $0.entryPath == "bgm_gos_theme.fsb" })

    let decoder = try VGMStreamDecoder(
        track: TrackItem(archiveURL: archiveURL, entryPath: entry.entryPath),
        sampleRate: 44_100
    )
    var chunks: [DecodedChunk] = []
    while chunks.count < 128, !decoder.trackEnded {
        let chunk = try decoder.decode(frameCount: 2_048)
        guard chunk.frameCount > 0 else { break }
        chunks.append(chunk)
    }
    #expect(!chunks.isEmpty)
    #expect(chunks.contains { chunk in
        chunk.left.contains(where: { $0 != 0 }) || chunk.right.contains(where: { $0 != 0 })
    })
}

@Test func joshWPCResidentEvilTXTPUsesCompleteArchiveMaterialization() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/PC/Resident Evil 3 (2020-04-03)(Capcom)[PC].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let module = try #require(GMEFormatSupport.module(forPathExtension: "txtp"))
    #expect(module.backend == .vgmstream)
    #expect(module.archiveMaterialization == .completeSet)
    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: SPCFileScanner.supportedExtensions
    )
    let entry = try #require(entries.first { $0.entryPath == "Play_bgm_chp0_suicide.txtp" })

    let decoder = try VGMStreamDecoder(
        track: TrackItem(archiveURL: archiveURL, entryPath: entry.entryPath),
        sampleRate: 44_100
    )
    let chunks = try (0..<4).map { _ in try decoder.decode(frameCount: 2_048) }
    #expect(chunks.allSatisfy { $0.frameCount > 0 })
}

@Test func joshWPCStandardAudioArchivesDecodeWAVAndMP3() throws {
    let fixtures: [(archiveURL: URL, entryPath: String, format: String)] = [
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/PC/Castlevania - The Arcade [Akumajou Dracula - The Arcade] (2009)(Konami)[PC].tar.zst"),
            "bgm040_title.wav",
            "WAV"
        ),
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/PC/Resident Evil [Biohazard] (1997)(Capcom)(Virgin)[PC].tar.zst"),
            "BGM_02.mp3",
            "MP3"
        )
    ]

    for fixture in fixtures where FileManager.default.fileExists(atPath: fixture.archiveURL.path) {
        let decoder = try StandardAudioDecoder(
            track: TrackItem(archiveURL: fixture.archiveURL, entryPath: fixture.entryPath),
            sampleRate: 44_100
        )
        #expect(try decoder.metadata().comment == fixture.format)
        var chunks: [DecodedChunk] = []
        while chunks.count < 128, !decoder.trackEnded {
            let chunk = try decoder.decode(frameCount: 2_048)
            guard chunk.frameCount > 0 else { break }
            chunks.append(chunk)
        }
        #expect(!chunks.isEmpty, "\(fixture.entryPath) did not produce PCM")
        #expect(chunks.contains { chunk in
            chunk.left.contains(where: { $0 != 0 }) || chunk.right.contains(where: { $0 != 0 })
        }, "\(fixture.entryPath) produced only silence")
    }
}

@Test func standardAudioSupportsAIFFWAVFLACAndMP3AcrossIntakeAndPlayback() throws {
    let fixtures = [
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/Derived/D (USA, Europe) [audio harvest v2]/disc-1/DArt/ITEMSEL.aiff"),
            "AIFF"
        ),
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/Mr. Norbert/Final Fantasy (NTSC - US) SFX - Cursor.wav"),
            "WAV"
        ),
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/Derived/D (USA) [audio harvest]/CDDA FLAC/D (USA) (Disc 1) (Track 2).flac"),
            "FLAC"
        ),
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/Mr. Norbert/Chiptune Artists/Kageyama Masashi/2-14 Stage 7(SOPHIA) DEMO.mp3"),
            "MP3"
        )
    ]

    for (fileURL, formatName) in fixtures {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
        let extensionName = fileURL.pathExtension.lowercased()

        #expect(GMEFormatSupport.playbackBackend(forPathExtension: extensionName) == .standardAudio)
        #expect(ScanCoreHandlers.registry.route(for: extensionName, archiveMember: false)?.pluginID == "standard-audio")
        #expect(PlaylistQueueLoader.canImportDroppedURL(fileURL))

        let inspector = try StandardAudioFileInspector(fileURL: fileURL)
        let metadata = try inspector.metadata(trackIndex: 0)
        #expect(metadata.system == "Standard Audio")
        #expect(metadata.comment == formatName)
        #expect(metadata.playLengthMs > 0)

        let decoder = try StandardAudioDecoder(track: TrackItem(url: fileURL), sampleRate: 44_100)
        var chunks: [DecodedChunk] = []
        while chunks.count < 128, !decoder.trackEnded {
            let chunk = try decoder.decode(frameCount: 2_048)
            guard chunk.frameCount > 0 else { break }
            chunks.append(chunk)
        }
        #expect(!chunks.isEmpty)
        #expect(chunks.contains { chunk in
            chunk.left.contains(where: { $0 != 0 }) || chunk.right.contains(where: { $0 != 0 })
        })
    }
}

@Test func standardAudioAACInM4AStreamsAndSeeksThroughTheSharedRoute() async throws {
    let sourceURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/Derived/D (USA, Europe) [audio harvest v2]/disc-1/DArt/ITEMSEL.aiff")
    guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let sourceMetadata = try StandardAudioFileInspector(fileURL: sourceURL).metadata(trackIndex: 0)
    let outputURL = temporaryDirectory.appendingPathComponent("fixture.m4a")
    _ = try await AudioExportAACService.export(
        requests: [
            AudioExportRequest(
                track: TrackItem(url: sourceURL),
                metadata: sourceMetadata,
                plan: PlaybackPlan(
                    preFadeSeconds: 1,
                    fadeSeconds: 0,
                    totalSeconds: 1,
                    usesNativeEnding: false,
                    isLongPlay: false
                ),
                outputURL: outputURL
            )
        ],
        progress: { _ in }
    )

    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "m4a") == .standardAudio)
    #expect(ScanCoreHandlers.registry.route(for: "m4a", archiveMember: false)?.pluginID == "standard-audio")
    let inspector = try StandardAudioFileInspector(fileURL: outputURL)
    let metadata = try inspector.metadata(trackIndex: 0)
    #expect(metadata.comment == "M4A")
    #expect(metadata.playLengthMs > 0)

    let decoder = try StandardAudioDecoder(track: TrackItem(url: outputURL), sampleRate: 44_100)
    try decoder.seek(toMilliseconds: 500)
    let chunk = try decoder.decode(frameCount: 2_048)
    #expect(chunk.frameCount > 0)
    #expect(chunk.left.contains(where: { $0 != 0 }) || chunk.right.contains(where: { $0 != 0 }))
}

@Test func dAIFFScansThroughTheSharedStandardAudioRoute() async throws {
    let fileURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/Derived/D (USA, Europe) [audio harvest v2]/disc-1/DArt/ITEMSEL.aiff")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: fileURL.path, archiveEntry: nil),
        fingerprint: ScanFingerprint(
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast
        ),
        sourceURL: fileURL,
        route: ScanCoreHandlers.registry.route(for: "aiff")
    )

    let results = await ScanPipelineExecutor().process(candidate)
    guard case .success(_, let inspection) = try #require(results.first) else {
        Issue.record("Expected D AIFF scan success")
        return
    }
    #expect(inspection.route.pluginID == "standard-audio")
    #expect(try #require(inspection.tracks.first?.metadata).comment == "AIFF")
}

@Test func standardAudioEOFReachesNativePlaybackCompletion() async throws {
    let fileURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/Mr. Norbert/Final Fantasy (NTSC - US) SFX - Cursor.wav")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    let playback = PlaybackEngine()
    let requestID = playback.reservePlaybackRequest()
    _ = try await playback.play(
        track: TrackItem(url: fileURL),
        plan: PlaybackPlan(
            preFadeSeconds: 1,
            fadeSeconds: 6,
            totalSeconds: 7,
            usesNativeEnding: false,
            isLongPlay: false
        ),
        requestID: requestID
    )

    for _ in 0..<80 {
        let snapshot = await playback.statusSnapshot()
        if snapshot.reachedEnd, !snapshot.isPlaying { return }
        try await Task.sleep(for: .milliseconds(50))
    }

    let snapshot = await playback.statusSnapshot()
    #expect(snapshot.reachedEnd)
    #expect(!snapshot.isPlaying)
}

@Test func droppedKOF96FLACArchiveReachesPlaylistCompletion() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW Zstd/NeoGeoCD Zstd/King of Fighters '96, The (1996-10-25)(SNK)[NGCD].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [archiveURL])
    let track = try #require(loaded.tracks.first { $0.filename == "NGCD-214E_02.flac" })
    #expect(track.isArchiveEntry)

    let playback = PlaybackEngine()
    let requestID = playback.reservePlaybackRequest()
    let metadata = try await playback.play(
        track: track,
        plan: PlaybackPlan(
            preFadeSeconds: 1,
            fadeSeconds: 0,
            totalSeconds: 1,
            usesNativeEnding: true,
            isLongPlay: false
        ),
        requestID: requestID
    )
    #expect(metadata.playLengthMs > 1_000)

    try await playback.seek(to: max(0, Double(metadata.playLengthMs) / 1_000 - 1))
    for _ in 0..<80 {
        let snapshot = await playback.statusSnapshot()
        if snapshot.reachedEnd, !snapshot.isPlaying { return }
        try await Task.sleep(for: .milliseconds(50))
    }

    let snapshot = await playback.statusSnapshot()
    #expect(snapshot.reachedEnd)
    #expect(!snapshot.isPlaying)
}

@MainActor
@Test func repeatOneRestartsAStandardAudioPlaylistTrackAfterEOF() async throws {
    let fileURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/Mr. Norbert/Final Fantasy (NTSC - US) SFX - Cursor.wav")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    let track = TrackItem(url: fileURL)
    let model = PlayerViewModel()
    model.playlist = [track]
    model.selectedTrackID = track.id
    model.selectedTrackIDs = [track.id]
    model.repeatMode = .song
    model.toggleTrackPlayback(track)

    // The fixture is 0.53 seconds. A playing state after one second proves
    // normal EOF returned through PlayerViewModel and Repeat One re-requested
    // the same ordinary playlist item.
    try await Task.sleep(for: .seconds(1))
    #expect(model.currentTrack?.id == track.id)
    #expect(model.isPlaying)

    model.toggleTrackPlayback(track)
}

@MainActor
@Test func standardAudioEOFAdvancesToTheNextPlaylistTrack() async throws {
    let wavURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/Mr. Norbert/Final Fantasy (NTSC - US) SFX - Cursor.wav")
    let flacURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/Derived/D (USA) [audio harvest]/CDDA FLAC/D (USA) (Disc 1) (Track 2).flac")
    guard FileManager.default.fileExists(atPath: wavURL.path),
          FileManager.default.fileExists(atPath: flacURL.path) else { return }

    let first = TrackItem(url: wavURL)
    let second = TrackItem(url: flacURL)
    let model = PlayerViewModel()
    model.playlist = [first, second]
    model.selectedTrackID = first.id
    model.selectedTrackIDs = [first.id]
    model.repeatMode = .off
    model.randomPlaybackScope = .off
    model.toggleTrackPlayback(first)

    try await Task.sleep(for: .seconds(1))
    #expect(model.currentTrack?.id == second.id, "status: \(model.statusText)")
    #expect(model.isPlaying, "status: \(model.statusText)")
    #expect(!model.isLoading, "status: \(model.statusText)")

    model.toggleTrackPlayback(second)
}

@Test func scannerLists3DOAIFCArchiveMembers() throws {
    let archiveURL = URL(fileURLWithPath: "/Volumes/128GB/JoshW/3DO/Out of This World [Another World] [Outer World] (1994-10-21)(Delphine)(Interplay)[3DO].7z")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: GMEFormatSupport.supportedExtensions
    )
    #expect(entries.count == 30)
    #expect(entries.allSatisfy { $0.entryPath.lowercased().hasSuffix(".aifc") })
    #expect(ScanCoreHandlers.registry.route(for: "aifc", archiveMember: true)?.pluginID == "vgmstream")

    let memberURL = try ZipArchiveSupport.materializeEntry(
        archiveURL: archiveURL,
        entryPath: try #require(entries.first?.entryPath)
    )
    let inspector = try VGMStreamFileInspector(fileURL: memberURL)
    #expect(inspector.trackCount == 1)
    let metadata = try inspector.metadata(trackIndex: 0)
    #expect(metadata.system == "3DO")
    #expect(metadata.playLengthMs > 0)

    let decoder = try VGMStreamDecoder(track: TrackItem(url: memberURL), sampleRate: 44_100)
    #expect(try decoder.decode(frameCount: 1_024).frameCount > 0)
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

@Test func xmRoutesToNativeOpenMPTBackend() throws {
    let module = try #require(GMEFormatSupport.module(forPathExtension: "XM"))
    #expect(module.pluginID == "openmpt")
    #expect(module.backend == .openMPT)
    #expect(module.archiveMaterialization == .selectedEntry)
    #expect(!module.requiresTrackEnumeration)
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

@Test func scanSelectionSeparatesNewAndIncrementalModes() {
    let identity = ScanItemIdentity(rootID: 1, path: "/music/set.gbs", archiveEntry: "song.gbs")
    let fingerprint = ScanFingerprint(fileSize: 10, modifiedAt: Date(timeIntervalSince1970: 1))
    let changed = ScanFingerprint(fileSize: 11, modifiedAt: Date(timeIntervalSince1970: 2))

    let successful = ScanInventoryItem(identity: identity, fingerprint: fingerprint, state: .successful, route: nil)
    #expect(!ScanSelection.includes(successful, mode: .incremental, currentFingerprint: fingerprint))
    #expect(ScanSelection.includes(successful, mode: .incremental, currentFingerprint: changed))
    #expect(ScanSelection.includes(successful, mode: .newScan, currentFingerprint: fingerprint))
}

@Test func archiveManifestSignatureSkipsTimestampOnlyChanges() {
    let identity = ScanItemIdentity(rootID: 1, path: "/music/set.7z", archiveEntry: nil)
    let previous = ScanFingerprint(
        fileSize: 100,
        modifiedAt: Date(timeIntervalSince1970: 1),
        contentSignature: "7zz-report:\nPath = song.vgm\nCRC = 1234"
    )
    let sameArchiveNewDate = ScanFingerprint(
        fileSize: 100,
        modifiedAt: Date(timeIntervalSince1970: 2),
        contentSignature: "7zz-report:\nPath = song.vgm\nCRC = 1234"
    )
    let changedArchive = ScanFingerprint(
        fileSize: 100,
        modifiedAt: Date(timeIntervalSince1970: 2),
        contentSignature: "7zz-report:\nPath = song.vgm\nCRC = 5678"
    )
    let successful = ScanInventoryItem(
        identity: identity,
        fingerprint: previous,
        state: .successful,
        route: nil
    )

    #expect(!ScanSelection.includes(
        successful,
        mode: .incremental,
        currentFingerprint: sameArchiveNewDate
    ))
    #expect(ScanSelection.includes(
        successful,
        mode: .incremental,
        currentFingerprint: changedArchive
    ))
}

@Test func scanMetadataShortcutsCentralizeFormatSpecificFastPaths() throws {
    func handler(for extensionName: String) throws -> any ScanFormatHandler {
        let module = try #require(GMEFormatSupport.module(forPathExtension: extensionName))
        return ScanMetadataShortcuts.handler(
            for: module,
            fallback: DecoderCoreScanHandler(descriptor: module.scanDescriptor)
        )
    }

    #expect(try handler(for: "spc") is SPCMetadataScanHandler)
    #expect(try handler(for: "vgm") is VGMMetadataScanHandler)
    #expect(try handler(for: "psf") is PSFMetadataScanHandler)
    #expect(try handler(for: "flac") is DecoderCoreScanHandler)
}

@Test func archiveSignaturesUseToolReportedContainerDetailsOnly() throws {
    let fixtures: [(URL, String)] = [
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/HES/r/Return to Zork (1995-05-27)(Data West)(NEC)[PC-FX].7z"),
            "7zz-report:"
        ),
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/Derived/NeuroDancer - Journey into the Neuronet! (USA) [audio harvest]/raw/NeuroDancer - Journey into the Neuronet! (USA).zip"),
            "7zz-report:"
        ),
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW Zstd/NeoGeoCD Zstd/King of Fighters '96, The (1996-10-25)(SNK)[NGCD].tar.zst"),
            "zstd-report:"
        )
    ]

    for (archiveURL, prefix) in fixtures where FileManager.default.fileExists(atPath: archiveURL.path) {
        let signature = try #require(try ZipArchiveSupport.scanSignature(for: archiveURL))
        #expect(signature.hasPrefix(prefix))
        #expect(!signature.contains("sha256"))
        #expect(!signature.contains("fnv"))
    }
}

@Test func completedDeepArchiveScanProducesParentSkipRecord() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/SNESMusicOrg Zstd/F-Zero.tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
    let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: archiveURL.path, archiveEntry: nil),
        fingerprint: ScanFingerprint(
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast,
            contentSignature: try ZipArchiveSupport.scanSignature(for: archiveURL)
        ),
        sourceURL: archiveURL,
        route: nil
    )

    let accumulator = try await ScanPipelineExecutor().process(
        plan: ScanPlan(mode: .newScan, candidates: [candidate]),
        persist: { _ in }
    )
    let results = await accumulator.results
    #expect(results.contains { result in
        guard case .archiveCompleted(let completed) = result else { return false }
        return completed.identity == candidate.identity
            && completed.fingerprint.contentSignature == candidate.fingerprint.contentSignature
    })
}

@MainActor
@Test func archiveCompletionPersistsItsSignatureForIncrementalSkipping() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-archive-signature-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"))
    try database.addRoot(path: directory.path)
    let root = try #require(database.loadRoots().first)
    let fingerprint = ScanFingerprint(
        fileSize: 1_024,
        modifiedAt: Date(timeIntervalSince1970: 1),
        contentSignature: "zstd-report:\nCheck: XXH64 deadbeef"
    )
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: root.id, path: "/music/example.tar.zst", archiveEntry: nil),
        fingerprint: fingerprint,
        sourceURL: URL(fileURLWithPath: "/music/example.tar.zst"),
        route: nil
    )

    try database.persistScanResults([.archiveCompleted(candidate)])
    let persisted = try #require(database.loadScanInventory(rootID: root.id).first)
    #expect(persisted.state == .successful)
    #expect(persisted.fingerprint.contentSignature == fingerprint.contentSignature)
    #expect(!ScanSelection.includes(
        persisted,
        mode: .incremental,
        currentFingerprint: ScanFingerprint(
            fileSize: 1_024,
            modifiedAt: Date(timeIntervalSince1970: 2),
            contentSignature: fingerprint.contentSignature
        )
    ))
}

@Test func libraryGameActivationUsesPersistedIndexedBuckets() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-browser-bucket-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"))
    try database.addRoot(path: directory.path)
    let root = try #require(database.loadRoots().first)
    let route = ScanRoute(
        pluginID: "gme",
        formatExtension: "spc",
        supportsArchiveMembers: true,
        supportsMultiTrack: false
    )
    let timestamp = Date(timeIntervalSince1970: 1)
    let gameFolder = directory.appendingPathComponent("Game", isDirectory: true)

    func result(path: String, title: String, game: String, system: String) -> ScanPipelineResult {
        let candidate = ScanCandidate(
            identity: ScanItemIdentity(rootID: root.id, path: path, archiveEntry: nil),
            fingerprint: ScanFingerprint(fileSize: 1, modifiedAt: timestamp),
            sourceURL: URL(fileURLWithPath: path),
            route: route
        )
        return .success(
            candidate,
            ScanInspection(
                route: route,
                tracks: [
                    ScanTrackMetadata(
                        trackIndex: 0,
                        trackCount: 1,
                        metadata: TrackMetadata(
                            game: game,
                            song: title,
                            system: system,
                            author: "",
                            comment: "",
                            introLengthMs: 0,
                            loopLengthMs: 0,
                            playLengthMs: 60_000,
                            fadeLengthMs: 0
                        )
                    )
                ]
            )
        )
    }

    try database.persistScanTrackResults([
        result(path: gameFolder.appendingPathComponent("one.spc").path, title: "One", game: "Game", system: "SNES"),
        result(path: gameFolder.appendingPathComponent("Nested/two.spc").path, title: "Two", game: "Game", system: "SNES"),
        result(path: directory.appendingPathComponent("other.spc").path, title: "Other", game: "Game", system: "Game Boy")
    ])

    let games = try database.loadGameItems()
    let selectedGame = try #require(games.first { $0.name == "Game" && $0.systemName == "SNES" })
    let loaded = try database.tracksAndMetadataForGames([selectedGame])
    let files = try database.loadFileItems()
    let sidebarContent = try LibraryDatabase.loadSidebarContent(databaseURL: database.databaseURL)
    let startupGames = try LibraryDatabase.loadGameSidebarItems(databaseURL: database.databaseURL)
    let deferredFiles = try LibraryDatabase.loadFileSidebarItems(databaseURL: database.databaseURL)
    let loadedFiles = try database.tracksAndMetadataForFiles(Array(files.prefix(2)))
    let queued = await PlaylistQueueLoader.loadLibraryTracks(
        databaseURL: database.databaseURL,
        request: .games([selectedGame])
    )
    let folderQueued = await PlaylistQueueLoader.loadLibraryTracks(
        databaseURL: database.databaseURL,
        request: .fileSidebar(
            fileItems: [],
            folders: [
                DatabaseFileSidebarFolder(
                    rootID: root.id,
                    rootPath: directory.path,
                    path: gameFolder.path
                )
            ]
        )
    )

    #expect(selectedGame.trackCount == 2)
    #expect(loaded.tracks.map(\.filename) == ["one.spc", "two.spc"])
    #expect(loaded.metadata.values.allSatisfy { $0.game == "Game" && $0.system == "SNES" })
    #expect(Set(files.map(\.filename)) == ["one.spc", "other.spc", "two.spc"])
    #expect(sidebarContent.gameItems == games)
    #expect(sidebarContent.fileItems == files)
    #expect(startupGames == games)
    #expect(deferredFiles == files)
    #expect(queued.tracks.map(\.filename) == ["one.spc", "two.spc"])
    #expect(folderQueued.tracks.map(\.filename) == ["one.spc", "two.spc"])
    #expect(loadedFiles.tracks.count == 2)
}

@Test func deadLinksStayReusableUntilExplicitlyDeleted() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-dead-links-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"))
    try database.addRoot(path: directory.path)
    let root = try #require(database.loadRoots().first)
    let path = directory.appendingPathComponent("retained.spc").path
    let route = ScanRoute(pluginID: "gme", formatExtension: "spc", supportsArchiveMembers: true, supportsMultiTrack: false)
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: root.id, path: path, archiveEntry: nil),
        fingerprint: ScanFingerprint(fileSize: 128, modifiedAt: .now),
        sourceURL: URL(fileURLWithPath: path),
        route: route
    )
    let inspection = ScanInspection(
        route: route,
        tracks: [ScanTrackMetadata(
            trackIndex: 0,
            trackCount: 1,
            metadata: TrackMetadata(
                game: "Retained",
                song: "Track",
                system: "SNES",
                author: "",
                comment: "",
                introLengthMs: 0,
                loopLengthMs: 0,
                playLengthMs: 0,
                fadeLengthMs: 0
            )
        )]
    )
    try database.persistScanTrackResults([.success(candidate, inspection)])
    #expect(try database.loadGameItems().count == 1)

    let source = LibraryIndexedSource(rootID: root.id, path: path, archiveEntry: nil)
    try database.markSourcesDead([source])
    #expect(try database.deadSourceCount() == 1)
    #expect(try database.loadGameItems().isEmpty)

    try database.restoreSources([source])
    #expect(try database.deadSourceCount() == 0)
    #expect(try database.loadGameItems().count == 1)

    try database.markSourcesDead([source])
    let summary = try LibraryDatabaseMaintenance.summary(databaseURL: database.databaseURL)
    #expect(summary.deadLinkCount == 1)
    #expect(summary.indexedTrackCount == 1)
    #expect(summary.unlinkedTrackCount == 1)
    #expect(summary.deadLinkSummaryText == "1 unlinked source retained")
    #expect(try LibraryDatabaseMaintenance.clearDeadLinks(databaseURL: database.databaseURL) == 1)
    #expect(try database.loadGameItems().isEmpty)
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
        mode: .incremental,
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

@Test func scanOperationTimeoutReturnsBeforeItsLimitForCompletedWork() async throws {
    let value = try await ScanOperationTimeout.run(kind: .archiveListing, description: "test") { 7 }
    #expect(value == 7)
}

@Test func deepScanMaterializesSelectedArchiveMembersInOneBatch() async throws {
    let archiveURL = URL(fileURLWithPath: "/music/album.7z")
    let fingerprint = ScanFingerprint(fileSize: 130_000, modifiedAt: Date(timeIntervalSince1970: 1))
    let entries = ["01.spc", "02.spc", "03.spc"]
    let route = ScanRoute(
        pluginID: "gme",
        formatExtension: "spc",
        supportsArchiveMembers: true,
        supportsMultiTrack: true
    )
    let provider = RecordingScanArchiveProvider(
        members: entries.map {
            ScanArchiveMember(
                archiveURL: archiveURL,
                entryPath: $0,
                fingerprint: fingerprint,
                route: route
            )
        }
    )
    let descriptor = ScanPluginDescriptor(
        pluginID: "gme",
        displayName: "Test GME",
        supportedExtensions: ["spc"],
        supportsMultiTrack: true
    )
    let handler = RecordingScanFormatHandler(descriptor: descriptor)
    let executor = ScanPipelineExecutor(
        pluginRegistry: ScanPluginRegistry(descriptors: [descriptor]),
        handlerRegistry: ScanPluginHandlerRegistry(handlers: [handler]),
        archiveProvider: provider
    )
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: archiveURL.path, archiveEntry: nil),
        fingerprint: fingerprint,
        sourceURL: archiveURL,
        route: nil
    )

    let results = await executor.process(candidate)
    let calls = await provider.calls()
    let inspectedURLs = await handler.inspectedURLs()

    #expect(results.count == entries.count + 1)
    #expect(results.filter { result in
        if case .success = result { return true }
        return false
    }.count == entries.count)
    #expect(results.contains { result in
        if case .archiveCompleted = result { return true }
        return false
    })
    #expect(calls.list == 1)
    #expect(calls.selectedEntry == 0)
    #expect(calls.selectedBatch == 1)
    #expect(calls.completeArchive == 0)
    #expect(calls.batchEntries == entries)
    #expect(Set(inspectedURLs.map(\.lastPathComponent)) == Set(entries))
}

@Test func deepScanPreservesCompleteArchiveMaterializationForDependencyFormats() async throws {
    let archiveURL = URL(fileURLWithPath: "/music/album.7z")
    let fingerprint = ScanFingerprint(fileSize: 1_000, modifiedAt: Date(timeIntervalSince1970: 1))
    let route = ScanRoute(
        pluginID: "play-psf2",
        formatExtension: "minipsf2",
        supportsArchiveMembers: true,
        supportsMultiTrack: false
    )
    let provider = RecordingScanArchiveProvider(members: [
        ScanArchiveMember(
            archiveURL: archiveURL,
            entryPath: "music/01.minipsf2",
            fingerprint: fingerprint,
            route: route
        )
    ])
    let descriptor = ScanPluginDescriptor(
        pluginID: "play-psf2",
        displayName: "Test PSF2",
        supportedExtensions: ["minipsf2"]
    )
    let executor = ScanPipelineExecutor(
        pluginRegistry: ScanPluginRegistry(descriptors: [descriptor]),
        handlerRegistry: ScanPluginHandlerRegistry(
            handlers: [RecordingScanFormatHandler(descriptor: descriptor)]
        ),
        archiveProvider: provider
    )
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: archiveURL.path, archiveEntry: nil),
        fingerprint: fingerprint,
        sourceURL: archiveURL,
        route: nil
    )

    let results = await executor.process(candidate)
    let calls = await provider.calls()

    #expect(results.count == 1)
    #expect(calls.selectedEntry == 0)
    #expect(calls.selectedBatch == 0)
    #expect(calls.completeArchive == 1)
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

private actor RecordingScanArchiveProvider: ScanArchiveProvider {
    private let members: [ScanArchiveMember]
    private var listCallCount = 0
    private var selectedEntryCallCount = 0
    private var selectedBatchCallCount = 0
    private var completeArchiveCallCount = 0
    private var selectedBatchEntries: [String] = []

    init(members: [ScanArchiveMember]) {
        self.members = members
    }

    func listMembers(
        in archiveURL: URL,
        supportedExtensions: Set<String>
    ) async throws -> ScanArchiveListing {
        listCallCount += 1
        return ScanArchiveListing(members: members, scanSignature: nil)
    }

    func materialize(archiveURL: URL, entryPath: String) async throws -> URL {
        selectedEntryCallCount += 1
        return URL(fileURLWithPath: "/materialized").appendingPathComponent(entryPath)
    }

    func materializeEntries(archiveURL: URL, entryPaths: [String]) async throws -> URL {
        selectedBatchCallCount += 1
        selectedBatchEntries = entryPaths
        return URL(fileURLWithPath: "/materialized")
    }

    func materializeArchive(at archiveURL: URL) async throws -> URL {
        completeArchiveCallCount += 1
        return URL(fileURLWithPath: "/materialized")
    }

    func calls() -> (
        list: Int,
        selectedEntry: Int,
        selectedBatch: Int,
        completeArchive: Int,
        batchEntries: [String]
    ) {
        (
            listCallCount,
            selectedEntryCallCount,
            selectedBatchCallCount,
            completeArchiveCallCount,
            selectedBatchEntries
        )
    }
}

private struct RecordingScanFormatHandler: ScanFormatHandler {
    let descriptor: ScanPluginDescriptor
    private let recorder = ScanURLRecorder()

    init(descriptor: ScanPluginDescriptor) {
        self.descriptor = descriptor
    }

    func inspect(fileURL: URL, route: ScanRoute) async throws -> ScanInspection {
        await recorder.append(fileURL)
        return ScanInspection(
            route: route,
            tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: nil)]
        )
    }

    func inspectedURLs() async -> [URL] {
        await recorder.values
    }
}

private actor ScanURLRecorder {
    private(set) var values: [URL] = []

    func append(_ url: URL) {
        values.append(url)
    }
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

@Test @MainActor func spectrumAnalyzerUsesConfigurableTenTwentyAndFortyBandLayouts() {
    let model = ToolbarSpectrumModel()
    #expect(model.bandCount == 10)
    model.configure(bandCount: 20)
    #expect(model.bandCount == 20)
    #expect(model.levels.count == 20)
    model.configure(bandCount: 40)
    #expect(model.bandCount == 40)
    #expect(model.capLevels.count == 40)
    #expect(SpectrumBandCount.clamped(999) == 40)
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
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "ssf") == .highlyTheoretical)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "minissf") == .highlyTheoretical)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "usf") == .lazyUSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "miniusf") == .lazyUSF)
}

@Test func decoderRegistryDeclaresPlaylistEnumerationCapability() {
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "PSF") == .playPSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "minipsf") == .playPSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "PSF2") == .playPSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "minipsf2") == .playPSF)
    #expect(!GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "psf2"))
    #expect(!GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "psf"))
    #expect(!GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "mini2sf"))
    #expect(!GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "spc"))
    #expect(GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "nsf"))
    #expect(GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "adx"))
    #expect(GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "xa"))
    #expect(GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "GENH"))
    #expect(GMEFormatSupport.module(forPathExtension: "minipsf")?.pluginID == "play-psf1")
    #expect(GMEFormatSupport.module(forPathExtension: "minipsf2")?.pluginID == "play-psf2")
    #expect(GMEFormatSupport.module(forPathExtension: "minissf")?.pluginID == "highly-theoretical")
    #expect(GMEFormatSupport.module(forPathExtension: "spc")?.pluginID == "gme")
    #expect(GMEFormatSupport.module(forPathExtension: "nsf")?.pluginID == "gme-multitrack")
    #expect(GMEFormatSupport.module(forPathExtension: "psf")?.archiveMaterialization == .completeSet)
    #expect(GMEFormatSupport.module(forPathExtension: "psf2")?.archiveMaterialization == .completeSet)
    #expect(GMEFormatSupport.module(forPathExtension: "minissf")?.archiveMaterialization == .completeSet)
    #expect(GMEFormatSupport.module(forPathExtension: "psf")?.scanArchiveMaterialization == .selectedEntry)
    #expect(GMEFormatSupport.module(forPathExtension: "psf2")?.scanArchiveMaterialization == .selectedEntry)
    #expect(GMEFormatSupport.module(forPathExtension: "miniusf")?.archiveMaterialization == .completeSetWithLazyUSFAliases)
    #expect(GMEFormatSupport.module(forPathExtension: "adx")?.archiveMaterialization == .selectedEntry)
    let expectedGMEConcurrency = min(
        3,
        max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    )
    #expect(GMEFormatSupport.module(forPathExtension: "spc")?.scanInspectionConcurrency == expectedGMEConcurrency)
    #expect(GMEFormatSupport.module(forPathExtension: "minipsf2")?.scanInspectionConcurrency == 1)
    #expect(GMEFormatSupport.scanPluginDescriptors.count == GMEFormatSupport.modules.count)
    #expect(ScanCoreHandlers.registry.route(for: "PSF", archiveMember: true)?.pluginID == "play-psf1")
    #expect(ScanCoreHandlers.registry.route(for: "PSF2", archiveMember: true)?.pluginID == "play-psf2")
    #expect(ScanCoreHandlers.registry.route(for: "MINISSF", archiveMember: true)?.pluginID == "highly-theoretical")
    #expect(ScanCoreHandlers.registry.route(for: "XA", archiveMember: true)?.pluginID == "vgmstream")
    #expect(ScanCoreHandlers.registry.route(for: "GENH", archiveMember: true)?.pluginID == "vgmstream")

    let registeredExtensionCount = GMEFormatSupport.modules.reduce(0) {
        $0 + $1.supportedExtensions.count
    }
    #expect(GMEFormatSupport.supportedExtensions.count == registeredExtensionCount)
}

@Test func archiveInspectionPolicyPreservesDependencySets() {
    #expect(GMEFormatSupport.archiveMaterializationForInspection(
        entryPaths: ["01.spc", "02.spc"]
    ) == .selectedEntry)
    #expect(GMEFormatSupport.archiveMaterializationForInspection(
        entryPaths: ["01.minipsf2", "02.psf2"]
    ) == .completeSet)
    #expect(GMEFormatSupport.archiveMaterializationForInspection(
        entryPaths: ["01.spc", "02.miniusf"]
    ) == .completeSetWithLazyUSFAliases)
}

@Test func archiveScanPolicyUsesSelectedPSFFamilyMembers() {
    #expect(GMEFormatSupport.scanArchiveMaterializationForInspection(
        entryPaths: ["01.minipsf2", "02.psf2"]
    ) == .selectedEntry)
    #expect(GMEFormatSupport.scanArchiveMaterializationForInspection(
        entryPaths: ["01.spc", "02.miniusf"]
    ) == .selectedEntry)
}

@Test func playlistMetadataPreparationBatchesArchiveMembersByContainer() {
    let firstArchive = URL(fileURLWithPath: "/music/first.7z")
    let secondArchive = URL(fileURLWithPath: "/music/second.zip")
    let batches = PlaybackInspection.archiveBatches(for: [
        TrackItem(archiveURL: firstArchive, entryPath: "01.spc"),
        TrackItem(archiveURL: firstArchive, entryPath: "01.spc", trackIndex: 1, trackCount: 2),
        TrackItem(url: URL(fileURLWithPath: "/music/direct.spc")),
        TrackItem(archiveURL: firstArchive, entryPath: "02.spc"),
        TrackItem(archiveURL: secondArchive, entryPath: "03.spc")
    ])

    #expect(batches == [
        PlaylistMetadataArchiveBatch(
            archiveURL: firstArchive.standardizedFileURL,
            entryPaths: ["01.spc", "02.spc"]
        ),
        PlaylistMetadataArchiveBatch(
            archiveURL: secondArchive.standardizedFileURL,
            entryPaths: ["03.spc"]
        )
    ])
    #expect(PlaybackInspection.metadataWorkerLimit == 2)
}

@Test func playlistMetadataPreparationUsesOneMaterializedSPCSet() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/SPC/0-9/3 Ninjas Kick Back (1994-11)(Malibu)(Sony Imagesoft)[SNES].7z")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: ["spc"]
    )
    let jobs = PlaybackInspection.prepareMetadataInspectionJobs(
        tracks: entries.map {
            TrackItem(archiveURL: archiveURL, entryPath: $0.entryPath)
        }
    )

    #expect(jobs.count == entries.count)
    #expect(jobs.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
    let selectionDirectories = Set(jobs.compactMap { job in
        job.fileURL.pathComponents.first(where: { $0.hasPrefix("selection-") })
    })
    #expect(selectionDirectories.count == 1)
    if let firstJob = jobs.first {
        let metadata = try await PlaybackInspection.inspectMetadata(
            track: firstJob.track,
            fileURL: firstJob.fileURL
        )
        #expect(metadata.playLengthMs > 0)
    }
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

@Test func completionAdvancesWithinTheCurrentQueueWithoutWrapping() {
    let first = TrackItem(url: URL(fileURLWithPath: "/tmp/one.spc"))
    let second = TrackItem(url: URL(fileURLWithPath: "/tmp/two.spc"))
    let third = TrackItem(url: URL(fileURLWithPath: "/tmp/three.spc"))
    let playlist = [first, second, third]

    #expect(QueueTransportNavigation.completionAdvanceTarget(
        currentTrack: first,
        playlist: playlist
    ) == second)
    #expect(QueueTransportNavigation.completionAdvanceTarget(
        currentTrack: third,
        playlist: playlist
    ) == nil)
}

@Test func completionStartsAtHeadWhenAReplacementQueueDoesNotContainPlayingTrack() {
    let oldTrack = TrackItem(url: URL(fileURLWithPath: "/tmp/old.spc"))
    let replacementFirst = TrackItem(url: URL(fileURLWithPath: "/tmp/new-one.spc"))
    let replacementSecond = TrackItem(url: URL(fileURLWithPath: "/tmp/new-two.spc"))

    #expect(QueueTransportNavigation.completionAdvanceTarget(
        currentTrack: oldTrack,
        playlist: [replacementFirst, replacementSecond]
    ) == replacementFirst)
    #expect(QueueTransportNavigation.completionAdvanceTarget(
        currentTrack: oldTrack,
        playlist: []
    ) == nil)
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

@Test func databaseFileSidebarBuildsAnExpandableScannedTree() {
    let rootPath = "/music/Library"
    let item = DatabaseFileItem(
        rootID: 1,
        rootPath: rootPath,
        folderPath: "/music/Library/Neo Geo CD/KOF 96",
        path: "/music/Library/Neo Geo CD/KOF 96/KOF96.tar.zst",
        isArchive: true,
        trackCount: 26
    )
    let rootID = DatabaseFileSidebarTree.folderID(rootID: 1, path: rootPath)
    let consoleID = DatabaseFileSidebarTree.folderID(rootID: 1, path: "/music/Library/Neo Geo CD")
    let gameID = DatabaseFileSidebarTree.folderID(rootID: 1, path: "/music/Library/Neo Geo CD/KOF 96")

    let collapsedRows = DatabaseFileSidebarTree.rows(items: [item], expandedFolderIDs: [rootID, consoleID])
    #expect(collapsedRows.contains(.folder(id: gameID, title: "KOF 96", depth: 2, isExpanded: false)))
    #expect(!collapsedRows.contains { $0.file == item })

    let expandedRows = DatabaseFileSidebarTree.rows(items: [item], expandedFolderIDs: [rootID, consoleID, gameID])
    #expect(expandedRows.contains { $0.file == item })
}

@MainActor
@Test func databaseFileSidebarKeepsLargeRootsCollapsedAfterLoading() {
    let sidebar = DatabaseFileSidebarState()
    let item = DatabaseFileItem(
        rootID: 1,
        rootPath: "/music/Library",
        folderPath: "/music/Library/Neo Geo CD",
        path: "/music/Library/Neo Geo CD/KOF96.tar.zst",
        isArchive: true,
        trackCount: 26
    )

    sidebar.replaceFileItems([item])

    let rootID = DatabaseFileSidebarTree.folderID(rootID: 1, path: "/music/Library")
    #expect(sidebar.expandedFolderIDs.isEmpty)
    #expect(DatabaseFileSidebarTree.rows(
        items: sidebar.visibleFileItems,
        expandedFolderIDs: sidebar.expandedFolderIDs
    ) == [.folder(id: rootID, title: "Library", depth: 0, isExpanded: false)])
}

@Test func fileSidebarDisclosureUsesPointGap() {
    let fontSize: CGFloat = 12
    let gap: CGFloat = 6
    #expect(DatabaseFileSidebarInteraction.indentationStep(fontSize: fontSize, gap: gap) == 17)
    #expect(DatabaseFileSidebarInteraction.isDisclosureHit(locationX: 4, depth: 0, fontSize: fontSize, gap: gap))
    #expect(DatabaseFileSidebarInteraction.isDisclosureHit(locationX: 21, depth: 1, fontSize: fontSize, gap: gap))
    #expect(!DatabaseFileSidebarInteraction.isDisclosureHit(locationX: 20, depth: 1, fontSize: fontSize, gap: gap))
    #expect(!DatabaseFileSidebarInteraction.isDisclosureHit(locationX: 32, depth: 1, fontSize: fontSize, gap: gap))
    #expect(DatabaseFileSidebarInteraction.indentationStep(fontSize: 18, gap: gap) == 23)
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

@Test func restoredSessionKeepsArchiveBackedTracks() throws {
    let suiteName = "CocoaSpiceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create isolated UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("7z")
    try Data().write(to: archiveURL)
    defer { try? FileManager.default.removeItem(at: archiveURL) }
    let track = TrackItem(archiveURL: archiveURL, entryPath: "Music/song.spc")
    defaults.set([track.persistedValue], forKey: AppDefaultsKey.persistedPlaylistPaths)
    defaults.set(true, forKey: AppDefaultsKey.longPlayEnabled)
    defaults.set("search", forKey: AppDefaultsKey.sidebarSearchText)
    defaults.set("/Music", forKey: AppDefaultsKey.lastRootPath)
    defaults.set("/Music/SNES", forKey: AppDefaultsKey.lastLibrarySelectedFolderPath)
    defaults.set(["title", "file"], forKey: AppDefaultsKey.playlistColumnOrder)

    let restored = AppSessionPersistence.restoreSessionState(
        defaults: defaults,
        supportedExtensions: ["spc"]
    )
    #expect(restored?.tracks == [track])

    let startup = AppSessionPersistence.restoreStartupState(
        defaults: defaults,
        supportedExtensions: ["spc"]
    )
    #expect(startup.playbackPreferences.longPlayEnabled)
    #expect(startup.sessionState?.tracks == [track])
    #expect(startup.playlistColumnState.order == ["title", "file"])
    #expect(startup.sidebarSearchText == "search")
    #expect(startup.lastRootPath == "/Music")
    #expect(startup.lastLibrarySelectedFolderPath == "/Music/SNES")
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

@Test func droppedArchiveM3UExpandsOnlyReferencedMembersInDeclaredOrder() async throws {
    #expect(FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"))

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let playlistDirectory = temporaryDirectory.appendingPathComponent("playlists", isDirectory: true)
    let audioDirectory = temporaryDirectory.appendingPathComponent("audio", isDirectory: true)
    try FileManager.default.createDirectory(at: playlistDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try Data("one".utf8).write(to: audioDirectory.appendingPathComponent("first.mp3"))
    try Data("two".utf8).write(to: audioDirectory.appendingPathComponent("second.mp3"))
    try Data("skip".utf8).write(to: audioDirectory.appendingPathComponent("not-listed.mp3"))
    try "#EXTM3U\n../audio/second.mp3\n../audio/first.mp3\nmissing.mp3\n".write(
        to: playlistDirectory.appendingPathComponent("queue.m3u"),
        atomically: true,
        encoding: .utf8
    )
    let archiveURL = temporaryDirectory.appendingPathComponent("Playlist.zip")
    try runProcess(
        executable: "/usr/bin/zip",
        arguments: ["-q", "-r", archiveURL.path, "playlists", "audio"],
        workingDirectory: temporaryDirectory
    )

    let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [archiveURL])

    #expect(loaded.tracks == [
        TrackItem(archiveURL: archiveURL, entryPath: "audio/second.mp3"),
        TrackItem(archiveURL: archiveURL, entryPath: "audio/first.mp3")
    ])
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

@Test func disablingEndFadeUsesTheTimedTrackNativeEnding() {
    let metadata = TrackMetadata(
        game: "",
        song: "",
        system: "",
        author: "",
        comment: "",
        introLengthMs: 0,
        loopLengthMs: 0,
        playLengthMs: 90_000,
        fadeLengthMs: 0
    )

    let plan = PlaybackTimingPolicy.playbackPlan(
        metadata: metadata,
        trackPathExtension: "spc",
        longPlayEnabled: false,
        manualPreFadeSeconds: 240,
        fadeSeconds: 0
    )

    #expect(plan.usesNativeEnding)
    #expect(plan.fadeSeconds == 0)
    #expect(plan.totalSeconds == 90)
}

@Test func longPlayPlanIsUniformForEveryRegisteredDecoderExtension() {
    for module in GMEFormatSupport.modules {
        for extensionName in module.supportedExtensions {
            let plan = PlaybackTimingPolicy.playbackPlan(
                metadata: nil,
                trackPathExtension: extensionName.uppercased(),
                longPlayEnabled: true,
                manualPreFadeSeconds: 240,
                fadeSeconds: 6
            )
            #expect(plan.isLongPlay, "Long Play was not enabled for \(extensionName)")
            #expect(!plan.usesNativeEnding, "Native ending was not suppressed for \(extensionName)")
            #expect(plan.preFadeSeconds == 240)
            #expect(plan.fadeSeconds == 6)
            #expect(plan.totalSeconds == 246)
        }
    }

    let unsupported = PlaybackTimingPolicy.playbackPlan(
        metadata: nil,
        trackPathExtension: "mp3",
        longPlayEnabled: true,
        manualPreFadeSeconds: 240,
        fadeSeconds: 6
    )
    #expect(!unsupported.isLongPlay)
    #expect(unsupported.usesNativeEnding)
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
    #expect(!legacyOnlyPreferences.spectrumEnabled)
    #expect(!legacyOnlyPreferences.databaseSidebarMonospaceFont)
    #expect(legacyOnlyPreferences.databaseSidebarDisclosureGap == nil)
    #expect(legacyOnlyPreferences.databaseSidebarDisclosureGapPoints == nil)
    #expect(!legacyOnlyPreferences.databaseSidebarHidesFileExtensions)
    #expect(!legacyOnlyPreferences.sidebarSystemMode)
    #expect(!legacyOnlyPreferences.equalizerEnabled)
    #expect(legacyOnlyPreferences.equalizerBandGains == nil)

    defaults.set(true, forKey: AppDefaultsKey.longPlayEnabled)
    defaults.set(240, forKey: AppDefaultsKey.manualPreFadeSeconds)
    defaults.set("0.100000,0.200000,0.300000,1.000000", forKey: AppDefaultsKey.spectrumGradientStartColor)
    defaults.set("0.900000,0.800000,0.700000,1.000000", forKey: AppDefaultsKey.spectrumGradientEndColor)
    defaults.set("0.400000,0.500000,0.600000,1.000000", forKey: AppDefaultsKey.spectrumPeakColor)
    defaults.set(true, forKey: AppDefaultsKey.sidebarSystemMode)
    defaults.set(true, forKey: AppDefaultsKey.databaseSidebarMonospaceFont)
    defaults.set(12, forKey: AppDefaultsKey.databaseSidebarDisclosureGapPoints)
    defaults.set(true, forKey: AppDefaultsKey.databaseSidebarHidesFileExtensions)
    defaults.set(15, forKey: AppDefaultsKey.playlistFontSize)
    defaults.set("tertiary", forKey: AppDefaultsKey.playlistTextColor)
    defaults.set(true, forKey: AppDefaultsKey.equalizerEnabled)
    defaults.set([-12.0, -3.5, 4.0, 12.0], forKey: AppDefaultsKey.equalizerBandGains)

    let unifiedPreferences = AppSessionPersistence.restorePlaybackPreferences(defaults: defaults)
    #expect(unifiedPreferences.longPlayEnabled)
    #expect(unifiedPreferences.manualPreFadeSeconds == 240)
    #expect(unifiedPreferences.spectrumGradientStartColor == "0.100000,0.200000,0.300000,1.000000")
    #expect(unifiedPreferences.spectrumGradientEndColor == "0.900000,0.800000,0.700000,1.000000")
    #expect(unifiedPreferences.spectrumPeakColor == "0.400000,0.500000,0.600000,1.000000")
    #expect(unifiedPreferences.databaseSidebarMonospaceFont)
    #expect(unifiedPreferences.databaseSidebarDisclosureGapPoints == 12)
    #expect(unifiedPreferences.databaseSidebarHidesFileExtensions)
    #expect(unifiedPreferences.playlistFontSize == 15)
    #expect(unifiedPreferences.playlistTextColor == "tertiary")
    #expect(unifiedPreferences.sidebarSystemMode)
    #expect(unifiedPreferences.equalizerEnabled)
    #expect(unifiedPreferences.equalizerBandGains == [-12.0, -3.5, 4.0, 12.0])
}

@Test func equalizerUsesTenStandardBandsAndClampsGain() {
    #expect(AudioEqualizer.bandFrequencies == [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000])
    #expect(AudioEqualizer.clampedGain(-20) == -12)
    #expect(AudioEqualizer.clampedGain(5.5) == 5.5)
    #expect(AudioEqualizer.clampedGain(20) == 12)
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
