import AppKit
import C2SF
import Foundation
import Testing
@testable import CocoaSpice

// Retain historic test names while production code uses the neutral registry.
private typealias GMEFormatSupport = PlaybackFormatRegistry

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
    defaults.set(true, forKey: AppDefaultsKey.monoEnabled)

    #expect(AppSessionPersistence.restorePlaybackPreferences(defaults: defaults).appVolume == 0.36)
    #expect(AppSessionPersistence.restorePlaybackPreferences(defaults: defaults).monoEnabled)
}

@Test func archiveCachePolicyPersistsModeAndNearestSupportedLimit() {
    let suiteName = "CocoaSpiceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create isolated UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let policy = ArchiveCachePolicy(mode: .disabled, maximumBytes: 1_024 * 1_024 * 1_024)
    policy.save(defaults: defaults)
    #expect(ArchiveCachePolicy.load(defaults: defaults) == policy)

    defaults.set(777 * 1_024 * 1_024, forKey: AppDefaultsKey.archiveCacheLimitBytes)
    #expect(ArchiveCachePolicy.load(defaults: defaults).maximumBytes == 1_024 * 1_024 * 1_024)
    #expect(ArchiveCachePolicy.load(defaults: defaults).activeLimitBytes == ArchiveCachePolicy.disposableLimitBytes)
}

@Test func monoRingBufferMixesStereoAndDuplicatesTheResult() throws {
    let ringBuffer = try RealtimePCMFrameRingBuffer(capacityFrames: 8)
    let left: [Float] = [1, 0.5, -1]
    let right: [Float] = [-1, 0, 0.5]
    let written = left.withUnsafeBufferPointer { leftPointer in
        right.withUnsafeBufferPointer { rightPointer in
            ringBuffer.writeMonoFromStereo(left: leftPointer, right: rightPointer)
        }
    }
    var renderedLeft = Array(repeating: Float.zero, count: 3)
    var renderedRight = Array(repeating: Float.zero, count: 3)
    let read = renderedLeft.withUnsafeMutableBufferPointer { leftPointer in
        renderedRight.withUnsafeMutableBufferPointer { rightPointer in
            ringBuffer.read(left: leftPointer, right: rightPointer)
        }
    }

    #expect(written == 3)
    #expect(read == 3)
    #expect(renderedLeft == [0, 0.25, -0.25])
    #expect(renderedRight == renderedLeft)
}

@MainActor
@Test func interfaceStyleUsesOneValueForSidebarAndPlaylist() {
    let model = PlayerViewModel()
    model.setDatabaseSidebarFontSize(15)
    model.setPlaylistTextColor(.secondary)
    model.setPlaylistMonospaceFont(true)

    #expect(model.databaseSidebarFontSize == 15)
    #expect(model.playlistFontSize == 15)
    #expect(model.databaseSidebarTextColor == .secondary)
    #expect(model.playlistTextColor == .secondary)
    #expect(model.databaseSidebarMonospaceFont)
    #expect(model.playlistMonospaceFont)
}

@Test func headerlessSS2ResourcesAreClassifiedAsUnsupported() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let rawURL = directory.appendingPathComponent("raw.ss2")
    let sshdURL = directory.appendingPathComponent("container.ss2")
    try Data([0x0B, 0x02, 0xF1, 0xF5]).write(to: rawURL)
    try Data("SShd".utf8).write(to: sshdURL)

    #expect(HeaderlessSS2Detector.isUnsupportedResource(rawURL))
    #expect(!HeaderlessSS2Detector.isUnsupportedResource(sshdURL))
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
