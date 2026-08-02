import AppKit
import C2SF
import Foundation
import Testing
@testable import CocoaSpice

// Retain historic test names while production code uses the neutral registry.
private typealias GMEFormatSupport = PlaybackFormatRegistry

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

@Test func joshWSaturnSOTNDVIScansAndDecodesThroughVGMStream() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/Sega Saturn/Akumajou Dracula X - Gekka no Yasoukyoku (1998-06-25)(KCE Tokyo)(KCE Nagoya)(Konami)[SAT].tar.zst")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }

    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "dvi") == .vgmstream)
    #expect(ScanCoreHandlers.registry.route(for: "dvi", archiveMember: true)?.pluginID == "vgmstream")
    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: SPCFileScanner.supportedExtensions
    )
    #expect(entries.count == 45)
    let entry = try #require(entries.first { $0.entryPath == "./02 Prologue.dvi" })

    let decoder = try VGMStreamDecoder(
        track: TrackItem(archiveURL: archiveURL, entryPath: entry.entryPath),
        sampleRate: 44_100
    )
    let metadata = try decoder.metadata()
    let chunks = try (0..<4).map { _ in try decoder.decode(frameCount: 2_048) }

    #expect(metadata.system == "Sega Saturn")
    #expect(chunks.allSatisfy { $0.frameCount == 2_048 })
    #expect(chunks.contains { chunk in
        chunk.left.contains(where: { abs($0) > 0.0001 }) || chunk.right.contains(where: { abs($0) > 0.0001 })
    })

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
    #expect(summary.completed == 45)
    #expect(summary.successful == 45)
    #expect(summary.failed == 0)
    #expect(summary.unsupported == 0)
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
