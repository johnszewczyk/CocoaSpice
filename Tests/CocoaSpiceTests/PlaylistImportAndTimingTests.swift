import AppKit
import C2SF
import Foundation
import Testing
@testable import CocoaSpice

// Retain historic test names while production code uses the neutral registry.
private typealias GMEFormatSupport = PlaybackFormatRegistry

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
@Test func longPlaySupportsLoopingCurrentPlayableFormats() {
    let model = PlayerViewModel()
    model.currentTrack = TrackItem(url: URL(fileURLWithPath: "/tmp/test.nsf"))
    #expect(model.currentTrackSupportsLongPlay)

    model.currentTrack = TrackItem(url: URL(fileURLWithPath: "/tmp/test.flac"))
    #expect(!model.currentTrackSupportsLongPlay)
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

@Test func longPlayPlanAppliesOnlyToLoopCapableDecoderExtensions() {
    for module in GMEFormatSupport.modules {
        for extensionName in module.supportedExtensions {
            let plan = PlaybackTimingPolicy.playbackPlan(
                metadata: nil,
                trackPathExtension: extensionName.uppercased(),
                longPlayEnabled: true,
                manualPreFadeSeconds: 240,
                fadeSeconds: 6
            )
            #expect(plan.isLongPlay == module.supportsLongPlay, "Unexpected Long Play policy for \(extensionName)")
            if module.supportsLongPlay {
                #expect(!plan.usesNativeEnding, "Native ending was not suppressed for \(extensionName)")
                #expect(plan.preFadeSeconds == 240)
                #expect(plan.fadeSeconds == 6)
                #expect(plan.totalSeconds == 246)
            } else {
                #expect(plan.usesNativeEnding, "Finite audio must retain its native ending for \(extensionName)")
            }
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
