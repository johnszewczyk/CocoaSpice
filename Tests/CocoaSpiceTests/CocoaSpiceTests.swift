import AppKit
import C2SF
import Foundation
import Testing
@testable import CocoaSpice

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
        sampleRate: 44_100
    )

    #expect(diagnostics.bufferedMilliseconds == 500)
    #expect(diagnostics.bufferPercent == 25)
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

@Test func standardAudioSupportsWAVAndFLACAcrossIntakeAndPlayback() throws {
    let fixtures = [
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/Mr. Norbert/Final Fantasy (NTSC - US) SFX - Cursor.wav"),
            "WAV"
        ),
        (
            URL(fileURLWithPath: "/Users/john/Downloads/audio/Derived/D (USA) [audio harvest]/CDDA FLAC/D (USA) (Disc 1) (Track 2).flac"),
            "FLAC"
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
        let chunks = try (0..<4).map { _ in try decoder.decode(frameCount: 2_048) }
        #expect(chunks.allSatisfy { $0.frameCount > 0 })
        #expect(chunks.contains { chunk in
            chunk.left.contains(where: { $0 != 0 }) || chunk.right.contains(where: { $0 != 0 })
        })
    }
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

@Test func fastScanIndexesArchiveMembersWithoutMetadataInspection() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/GBS/3D Ultra Pinball - Thrillride (2000-12)(Left Field)(Sierra)[GBC].7z")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
    let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: archiveURL.path, archiveEntry: nil),
        fingerprint: ScanFingerprint(fileSize: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate ?? .distantPast),
        sourceURL: archiveURL,
        route: nil
    )

    let accumulator = try await ScanPipelineExecutor(archiveScanDepth: .fast).process(
        plan: ScanPlan(mode: .newScan, candidates: [candidate]),
        persist: { _ in }
    )
    let results = await accumulator.results
    let inspections = results.compactMap { result -> ScanInspection? in
        guard case .success(_, let inspection) = result else { return nil }
        return inspection
    }

    #expect(inspections.count == 10)
    #expect(inspections.allSatisfy {
        $0.tracks.count == 1
            && $0.tracks[0].metadata?.comment == FastScanPlaceholder.metadataComment
    })
}

@Test func fastLibraryQueueExpandsMultiTrackNSFArchiveMember() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/ZopharsDomain/NSF/President no Sentaku (EMU).zophar.zip")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    let container = TrackItem(url: archiveURL)
    let loaded = LoadedPlaylistData(
        tracks: [container],
        metadata: [
            container.id: TrackMetadata(
                game: "President no Sentaku (EMU).zophar",
                song: "President no Sentaku (EMU).zophar",
                system: "",
                author: "",
                comment: FastScanPlaceholder.metadataComment,
                introLengthMs: 0,
                loopLengthMs: 0,
                playLengthMs: 0,
                fadeLengthMs: 0
            )
        ],
        widthHints: PlaylistColumnWidthHints(
            indexText: "1",
            fileText: "",
            titleText: "",
            gameText: "",
            authorText: "",
            systemText: "",
            lengthText: "—"
        )
    )

    let expanded = await PlaylistQueueLoader.expandFastContainers(in: loaded)

    #expect(expanded.tracks.count == 5)
    #expect(expanded.tracks.allSatisfy { $0.isArchiveEntry })
    #expect(Set(expanded.tracks.map(\.trackIndex)) == Set(0..<5))
    #expect(expanded.tracks.allSatisfy { expanded.metadata[$0.id]?.comment != FastScanPlaceholder.metadataComment })
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

    #expect(results.count == entries.count)
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

@Test @MainActor func spectrumAnalyzerUsesEightBands() {
    #expect(ToolbarSpectrumModel.bandCount == 8)
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
    #expect(GMEFormatSupport.module(forPathExtension: "spc")?.pluginID == "gme")
    #expect(GMEFormatSupport.module(forPathExtension: "nsf")?.pluginID == "gme-multitrack")
    #expect(GMEFormatSupport.module(forPathExtension: "psf")?.archiveMaterialization == .completeSet)
    #expect(GMEFormatSupport.module(forPathExtension: "psf2")?.archiveMaterialization == .completeSet)
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

    let restored = AppSessionPersistence.restoreSessionState(
        defaults: defaults,
        supportedExtensions: ["spc"]
    )
    #expect(restored?.tracks == [track])
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
    #expect(!legacyOnlyPreferences.databaseSidebarMonospaceFont)
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
    defaults.set(true, forKey: AppDefaultsKey.equalizerEnabled)
    defaults.set([-12.0, -3.5, 4.0, 12.0], forKey: AppDefaultsKey.equalizerBandGains)

    let unifiedPreferences = AppSessionPersistence.restorePlaybackPreferences(defaults: defaults)
    #expect(unifiedPreferences.longPlayEnabled)
    #expect(unifiedPreferences.manualPreFadeSeconds == 240)
    #expect(unifiedPreferences.spectrumGradientStartColor == "0.100000,0.200000,0.300000,1.000000")
    #expect(unifiedPreferences.spectrumGradientEndColor == "0.900000,0.800000,0.700000,1.000000")
    #expect(unifiedPreferences.spectrumPeakColor == "0.400000,0.500000,0.600000,1.000000")
    #expect(unifiedPreferences.databaseSidebarMonospaceFont)
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
