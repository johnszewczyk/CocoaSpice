import AppKit
import C2SF
import Foundation
import Testing
@testable import CocoaSpice

// Retain historic test names while production code uses the neutral registry.
private typealias GMEFormatSupport = PlaybackFormatRegistry

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

@Test func archivePlaybackCacheKeyChangesWhenArchiveSizeChangesAtSameModificationDate() throws {
    let archiveURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("tar.zst")
    defer { try? FileManager.default.removeItem(at: archiveURL) }

    let preservedDate = Date(timeIntervalSinceReferenceDate: 1_234_567)
    try Data([0]).write(to: archiveURL)
    try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: archiveURL.path)
    let originalCacheURL = ZipArchiveSupport.archiveCacheURL(for: archiveURL)

    try Data([0, 1]).write(to: archiveURL)
    try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: archiveURL.path)
    let repackedCacheURL = ZipArchiveSupport.archiveCacheURL(for: archiveURL)

    #expect(originalCacheURL != repackedCacheURL)
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
