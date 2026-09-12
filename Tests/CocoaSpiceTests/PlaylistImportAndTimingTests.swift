import Foundation
import Testing
import VGMBoyKit
@testable import CocoaSpice

@Test func archivePreparationUsesVGMBoyFormatCapabilities() throws {
    #expect(PlaybackFormatRegistry.archiveMaterialization(for: ["track.flac"]) == .selectedEntry)
    #expect(PlaybackFormatRegistry.archiveMaterialization(for: ["track.psf"]) == .completeSet)
    #expect(
        PlaybackFormatRegistry.archiveMaterialization(for: ["track.usf"])
            == .completeSetWithLazyUSFAliases
    )
    #expect(PlaybackFormatRegistry.archiveMaterialization(for: ["track.miniqsf"]) == .completeSet)
    #expect(PlaybackFormatRegistry.archiveMaterialization(for: ["track.unknown"]) == nil)
}

@Test func amigaArchiveUsesPrefixAdmissionAndCompleteSetMaterialization() throws {
    let archiveURL = URL(fileURLWithPath: "/tmp/music.lha")
    #expect(ZipArchiveSupport.canHandle(archiveURL))
    #expect(PlaybackFormatRegistry.admits(fileURL: URL(fileURLWithPath: "/tmp/Xpose/mod.xpose-end")))
    #expect(PlaybackFormatRegistry.archiveMaterialization(for: ["Xpose/mod.xpose-end"]) == .completeSet)
    #expect(!PlaybackFormatRegistry.admits(fileURL: URL(fileURLWithPath: "/tmp/stage.p4x")))
}

@Test(
    "Real Amiga LHA archive lists its prefix-led module",
    .enabled(
        if: ProcessInfo.processInfo.environment["COCOASPICE_AMIGA_ARCHIVE"] != nil,
        "Set COCOASPICE_AMIGA_ARCHIVE to run the real Amiga LHA listing check."
    )
)
func realAmigaLHAArchiveListsPrefixLedModule() async throws {
    let archivePath = try #require(ProcessInfo.processInfo.environment["COCOASPICE_AMIGA_ARCHIVE"])
    let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [URL(fileURLWithPath: archivePath)])

    #expect(loaded.tracks.count == 1)
    #expect(loaded.tracks.first?.archiveEntryPath == "Xpose/mod.xpose-end")
}

@Test func standaloneZstandardListingUsesItsImplicitPlayableMember() throws {
    let archiveURL = URL(fileURLWithPath: "/tmp/track.vgm.zst")
    let listing = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: ["vgm"]
    )
    #expect(listing.count == 1)
    #expect(listing[0].entryPath == "track.vgm")
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

    #expect(PlaybackFormatRegistry.supportedExtensions.contains("spc"))
    #expect(try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: PlaybackFormatRegistry.supportedExtensions
    ).count == 1)
    let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [archiveURL])
    #expect(loaded.tracks.count == 1)
    #expect(loaded.tracks[0].isArchiveEntry)
    #expect(loaded.tracks[0].url == archiveURL.standardizedFileURL)
    #expect(loaded.tracks[0].archiveEntryPath == "test.spc")

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

}

@Test func droppedAmigaPrefixModuleCreatesArchiveTrack() async throws {
    let sevenZipPath = "/opt/homebrew/bin/7zz"
    guard FileManager.default.isExecutableFile(atPath: sevenZipPath) else { return }

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let moduleDirectory = temporaryDirectory.appendingPathComponent("Xpose", isDirectory: true)
    try FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let moduleURL = moduleDirectory.appendingPathComponent("mod.xpose-end")
    try Data("not-a-real-amiga-module".utf8).write(to: moduleURL)
    let archiveURL = temporaryDirectory.appendingPathComponent("Xpose.7z")

    try runProcess(
        executable: sevenZipPath,
        arguments: ["a", "-bd", "-y", archiveURL.path, "Xpose/mod.xpose-end"],
        workingDirectory: temporaryDirectory
    )

    let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [archiveURL])
    #expect(loaded.tracks.count == 1)
    #expect(loaded.tracks[0].isArchiveEntry)
    #expect(loaded.tracks[0].archiveEntryPath == "Xpose/mod.xpose-end")
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

    try Data("one".utf8).write(to: audioDirectory.appendingPathComponent("first.wav"))
    try Data("two".utf8).write(to: audioDirectory.appendingPathComponent("second.wav"))
    try Data("skip".utf8).write(to: audioDirectory.appendingPathComponent("not-listed.wav"))
    try "#EXTM3U\n../audio/second.wav\n../audio/first.wav\nmissing.wav\n".write(
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
        TrackItem(archiveURL: archiveURL, entryPath: "audio/second.wav"),
        TrackItem(archiveURL: archiveURL, entryPath: "audio/first.wav")
    ])
}

@MainActor
@Test func longPlaySupportsLoopingCurrentPlayableFormats() {
    let model = PlayerViewModel()
    model.currentTrack = TrackItem(url: URL(fileURLWithPath: "/tmp/test.nsf"))
    #expect(model.currentTrackSupportsLongPlay)

    model.currentTrack = TrackItem(url: URL(fileURLWithPath: "/tmp/test.flac"))
    #expect(!model.currentTrackSupportsLongPlay)
}

@Test func optionsControlSurfaceIsVersionedAndCodable() throws {
    let surface = CocoaSpiceFrontendSurface.v1
    #expect(surface.version == CocoaSpiceFrontendProtocol.version)
    #expect(surface.supports(.options))
    #expect(surface.supports(.mainPlayback))
    #expect(surface.vgmboyEndpointSurface.supports(.playback, .setTempo))
    #expect(surface.vgmboyEndpointSurface.supports(.audio, .setEqualizer))
    #expect(surface.vgmboyEndpointSurface.supports(.export, .exportAAC))

    let command = CocoaSpiceOptionsCommand.setEqualizerBand(index: 4, gain: 3.5)
    let decoded = try JSONDecoder().decode(
        CocoaSpiceOptionsCommand.self,
        from: JSONEncoder().encode(command)
    )
    #expect(decoded == command)

    let playbackCommand = CocoaSpiceMainPlaybackCommand.seek(seconds: 42.5)
    let decodedPlaybackCommand = try JSONDecoder().decode(
        CocoaSpiceMainPlaybackCommand.self,
        from: JSONEncoder().encode(playbackCommand)
    )
    #expect(decodedPlaybackCommand == playbackCommand)
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

@Test func unknownDurationDefaultIsIndependentFromLongPlayTarget() {
    let plan = PlaybackTimingPolicy.playbackPlan(
        metadata: nil,
        trackPathExtension: "sid",
        longPlayEnabled: false,
        manualPreFadeSeconds: 240,
        fadeSeconds: 6,
        unknownDurationSeconds: 300
    )

    #expect(!plan.isLongPlay)
    #expect(plan.preFadeSeconds == 300)
    #expect(plan.totalSeconds == 306)

    let longPlay = PlaybackTimingPolicy.playbackPlan(
        metadata: nil,
        trackPathExtension: "sid",
        longPlayEnabled: true,
        manualPreFadeSeconds: 240,
        fadeSeconds: 6,
        unknownDurationSeconds: 300
    )
    #expect(longPlay.isLongPlay)
    #expect(longPlay.preFadeSeconds == 240)
}

@Test func longPlayLeavesFiniteCoreAudioDurationUntouched() {
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
        trackPathExtension: "flac",
        longPlayEnabled: true,
        manualPreFadeSeconds: 240,
        fadeSeconds: 6
    )

    #expect(!plan.isLongPlay)
    #expect(!plan.usesNativeEnding)
    #expect(plan.totalSeconds == 96)
}

@Test func longPlayPlanAppliesOnlyToLoopCapableDecoderExtensions() throws {
    for extensionName in PlaybackFormatRegistry.supportedExtensions {
        let supportsLongPlay = try #require(
            FormatRegistry.family(for: "track.\(extensionName)")?.supportsLongPlay as Bool?
        )
        let plan = PlaybackTimingPolicy.playbackPlan(
            metadata: nil,
            trackPathExtension: extensionName.uppercased(),
            longPlayEnabled: true,
            manualPreFadeSeconds: 240,
            fadeSeconds: 6
        )
        #expect(plan.isLongPlay == supportsLongPlay, "Unexpected Long Play policy for \(extensionName)")
        if supportsLongPlay {
            #expect(!plan.usesNativeEnding, "Native ending was not suppressed for \(extensionName)")
            #expect(plan.preFadeSeconds == 240)
            #expect(plan.fadeSeconds == 6)
            #expect(plan.totalSeconds == 246)
        } else {
            #expect(plan.usesNativeEnding, "Finite audio must retain its native ending for \(extensionName)")
        }
    }

    let unsupported = PlaybackTimingPolicy.playbackPlan(
        metadata: nil,
        trackPathExtension: "mus",
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
    #expect(legacyOnlyPreferences.databaseSidebarDisclosureGap == nil)
    #expect(legacyOnlyPreferences.databaseSidebarDisclosureGapPoints == nil)
    #expect(!legacyOnlyPreferences.databaseSidebarHidesFileExtensions)
    #expect(!legacyOnlyPreferences.sidebarSystemMode)
    #expect(!legacyOnlyPreferences.equalizerEnabled)
    #expect(legacyOnlyPreferences.equalizerBandGains == nil)

    defaults.set(true, forKey: AppDefaultsKey.longPlayEnabled)
    defaults.set(240, forKey: AppDefaultsKey.manualPreFadeSeconds)
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

@Test func directImportsUseOnlyDisplayFallbacks() {
    let track = TrackItem(url: URL(fileURLWithPath: "/music/Example/Game Theme.spc"))
    #expect(PlaylistPresentation.titleText(for: track, metadata: nil) == "Game Theme")
    #expect(PlaylistPresentation.gameText(for: track, metadata: nil) == "Example")
    #expect(PlaylistPresentation.authorText(for: nil) == "—")
    #expect(PlaylistPresentation.systemText(for: nil) == "—")
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
