import Foundation
import Testing
@testable import CocoaSpice

private typealias GMEFormatSupport = PlaybackFormatRegistry

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

@Test func scanActivitySeparatesSourcePathFromDisplayFilename() {
    let archiveURL = URL(fileURLWithPath: "/music/Katamari.tar.zst")
    let archiveCandidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: archiveURL.path, archiveEntry: nil),
        fingerprint: ScanFingerprint(fileSize: 1, modifiedAt: .distantPast),
        sourceURL: archiveURL,
        route: nil
    )
    let memberCandidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: 1, path: archiveURL.path, archiveEntry: "music/title.txtp"),
        fingerprint: ScanFingerprint(fileSize: 1, modifiedAt: .distantPast),
        sourceURL: archiveURL,
        route: nil
    )

    #expect(ScanActivity(candidate: archiveCandidate, detail: "Listing").sourcePath == archiveURL.path)
    #expect(ScanActivity(candidate: archiveCandidate, detail: "Listing").filename == "Katamari.tar.zst")
    #expect(ScanActivity(candidate: memberCandidate, detail: "Inspecting").sourcePath == "\(archiveURL.path)#music/title.txtp")
    #expect(ScanActivity(candidate: memberCandidate, detail: "Inspecting").filename == "title.txtp")
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

@Test func archiveRefreshReplacesMembersWhosePathsWereNormalizedByRepacking() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-archive-member-refresh-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"))
    try database.addRoot(path: directory.path)
    let root = try #require(database.loadRoots().first)
    let archivePath = directory.appendingPathComponent("Example.tar.zst").path
    let route = ScanRoute(
        pluginID: "gme",
        formatExtension: "vgz",
        supportsArchiveMembers: true,
        supportsMultiTrack: false
    )

    func result(entry: String, size: Int64) -> ScanPipelineResult {
        let candidate = ScanCandidate(
            identity: ScanItemIdentity(rootID: root.id, path: archivePath, archiveEntry: entry),
            fingerprint: ScanFingerprint(fileSize: size, modifiedAt: .now),
            sourceURL: URL(fileURLWithPath: archivePath),
            route: route
        )
        return .success(candidate, ScanInspection(
            route: route,
            tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: nil)]
        ))
    }

    try database.persistScanResults([result(entry: "01 - Title Screen.vgz", size: 16_212)])
    try database.resetArchiveMembers(rootID: root.id, path: archivePath)
    try database.persistScanResults([result(entry: "./01 - Title Screen.vgz", size: 16_733)])

    #expect(try database.trackCount() == 1)
    let inventory = try database.loadScanInventory(rootID: root.id)
    #expect(inventory.count == 1)
    #expect(inventory[0].identity.archiveEntry == "./01 - Title Screen.vgz")
}

@Test func staleArchiveMembersFromThePreReplacementScannerAreRepaired() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-stale-archive-member-repair-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"))
    try database.addRoot(path: directory.path)
    let root = try #require(database.loadRoots().first)
    let archivePath = directory.appendingPathComponent("Cool Spot.tar.zst").path
    let route = ScanRoute(
        pluginID: "libvgm",
        formatExtension: "vgz",
        supportsArchiveMembers: true,
        supportsMultiTrack: false
    )
    let oldFingerprint = ScanFingerprint(fileSize: 797_956, modifiedAt: Date(timeIntervalSince1970: 1))
    let currentFingerprint = ScanFingerprint(fileSize: 800_289, modifiedAt: Date(timeIntervalSince1970: 2))

    func member(entry: String, fingerprint: ScanFingerprint) -> ScanPipelineResult {
        .success(
            ScanCandidate(
                identity: ScanItemIdentity(rootID: root.id, path: archivePath, archiveEntry: entry),
                fingerprint: fingerprint,
                sourceURL: URL(fileURLWithPath: archivePath),
                route: route
            ),
            ScanInspection(route: route, tracks: [
                ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: nil)
            ])
        )
    }

    let parent = ScanCandidate(
        identity: ScanItemIdentity(rootID: root.id, path: archivePath, archiveEntry: nil),
        fingerprint: currentFingerprint,
        sourceURL: URL(fileURLWithPath: archivePath),
        route: nil
    )
    try database.persistScanResults([
        member(entry: "01 - Wipeout Tune.vgz", fingerprint: oldFingerprint),
        member(entry: "./01 - Wipeout Tune.vgz", fingerprint: currentFingerprint),
        .archiveCompleted(parent)
    ])

    try database.pruneStaleArchiveMembers()

    #expect(try database.trackCount() == 1)
    let inventory = try database.loadScanInventory(rootID: root.id)
    #expect(inventory.count == 2)
    #expect(inventory.contains { $0.identity.archiveEntry == "./01 - Wipeout Tune.vgz" })
    #expect(!inventory.contains { $0.identity.archiveEntry == "01 - Wipeout Tune.vgz" })
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

@Test func deepScanUsesSelectedInspectionForDependencyFormats() async throws {
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

    #expect(results.count == 2)
    #expect(calls.selectedEntry == 0)
    #expect(calls.selectedBatch == 1)
    #expect(calls.completeArchive == 0)
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
