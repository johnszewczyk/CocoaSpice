import AppKit
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
}

@Test func supportedExtensionsPreserveLegacyS98Compatibility() {
    #expect(SPCFileScanner.supportedExtensions.contains("s98"))
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

    defaults.set(true, forKey: AppDefaultsKey.longPlayEnabled)
    defaults.set(240, forKey: AppDefaultsKey.manualPreFadeSeconds)
    defaults.set("0.100000,0.200000,0.300000,1.000000", forKey: AppDefaultsKey.spectrumGradientStartColor)
    defaults.set("0.900000,0.800000,0.700000,1.000000", forKey: AppDefaultsKey.spectrumGradientEndColor)
    defaults.set("0.400000,0.500000,0.600000,1.000000", forKey: AppDefaultsKey.spectrumPeakColor)

    let unifiedPreferences = AppSessionPersistence.restorePlaybackPreferences(defaults: defaults)
    #expect(unifiedPreferences.longPlayEnabled)
    #expect(unifiedPreferences.manualPreFadeSeconds == 240)
    #expect(unifiedPreferences.spectrumGradientStartColor == "0.100000,0.200000,0.300000,1.000000")
    #expect(unifiedPreferences.spectrumGradientEndColor == "0.900000,0.800000,0.700000,1.000000")
    #expect(unifiedPreferences.spectrumPeakColor == "0.400000,0.500000,0.600000,1.000000")
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
