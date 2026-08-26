import AppKit
import CatalogReader
import Foundation
import Testing
@testable import CocoaSpice

@Test func sidebarSearchIsAViewIndependentTemporaryGamesView() {
    #expect(PlayerViewModel.effectiveSidebarBrowserMode(storedMode: .games, searchText: "Castlevania") == .games)
    #expect(PlayerViewModel.effectiveSidebarBrowserMode(storedMode: .files, searchText: "Castlevania") == .games)
    #expect(PlayerViewModel.effectiveSidebarBrowserMode(storedMode: .files, searchText: "  ") == .files)
}

@Test func databaseSidebarDisambiguatesDuplicateGameTitlesBySystem() {
    let items = CatalogBrowser.databaseGameItems(from: [
        CatalogGameBucket(rootID: 1, rootPath: "/music/JoshW", game: "Mega Man", system: "NES", trackCount: 10),
        CatalogGameBucket(rootID: 2, rootPath: "/music/SNESMusicOrg", game: "Mega Man", system: "Game Boy", trackCount: 12),
        CatalogGameBucket(rootID: 1, rootPath: "/music/JoshW", game: "Actraiser", system: "SNES", trackCount: 18)
    ])

    #expect(items.map(\.name) == ["Actraiser", "Mega Man", "Mega Man"])
    #expect(items[1].id != items[2].id)
    #expect(items[1].displayName == "Mega Man (Game Boy)")
    #expect(items[2].displayName == "Mega Man (NES)")
    #expect(items[2].searchableName.contains("nes"))
}

@Test func displayNamesStripWholeCompressedTarSuffixes() {
    #expect(FilenamePresentation.withoutDisplayedExtension("Cool Spot.tar.zst") == "Cool Spot")
    #expect(FilenamePresentation.withoutDisplayedExtension("Sonic.ZOPHAR.TAR.ZST") == "Sonic.ZOPHAR")
    #expect(FilenamePresentation.withoutDisplayedExtension("Theme.spc") == "Theme")

    let archiveTrack = TrackItem(
        archiveURL: URL(fileURLWithPath: "/music/Cool Spot.tar.zst"),
        entryPath: "Theme.spc"
    )
    #expect(archiveTrack.groupDisplayName == "Cool Spot.tar.zst")
    #expect(archiveTrack.displayName == "Theme")
}

@Test func databaseGameSearchIndexNarrowsPrefixQueriesAndRebuildsAfterBackspace() {
    var index = DatabaseGameSearchIndex(items: [
        DatabaseGameItem(rootID: 1, rootPath: "/music/JoshW", name: "Actraiser", systemName: "SNES", trackCount: 18),
        DatabaseGameItem(rootID: 1, rootPath: "/music/JoshW", name: "ActRaiser 2", systemName: "SNES", trackCount: 20),
        DatabaseGameItem(rootID: 1, rootPath: "/music/JoshW", name: "Chrono Trigger", systemName: "SNES", trackCount: 64)
    ])

    #expect(index.items(matching: "act").map(\.name) == ["Actraiser", "ActRaiser 2"])
    #expect(index.items(matching: "act 2").map(\.name) == ["ActRaiser 2"])
    #expect(index.items(matching: "chrono").map(\.name) == ["Chrono Trigger"])
    #expect(index.items(matching: "").count == 3)
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

@Test func databaseFileSidebarIndexMatchesTreeRowsForExpansionStates() {
    let rootPath = "/music/Library"
    let items = [
        DatabaseFileItem(
            rootID: 1,
            rootPath: rootPath,
            folderPath: "/music/Library/Neo Geo CD/KOF 96",
            path: "/music/Library/Neo Geo CD/KOF 96/KOF96.tar.zst",
            isArchive: true,
            trackCount: 26
        ),
        DatabaseFileItem(
            rootID: 1,
            rootPath: rootPath,
            folderPath: "/music/Library/NES",
            path: "/music/Library/NES/Actraiser.nsf",
            isArchive: false,
            trackCount: 18
        )
    ]
    let rootID = DatabaseFileSidebarTree.folderID(rootID: 1, path: rootPath)
    let consoleID = DatabaseFileSidebarTree.folderID(rootID: 1, path: "/music/Library/Neo Geo CD")
    let gameID = DatabaseFileSidebarTree.folderID(rootID: 1, path: "/music/Library/Neo Geo CD/KOF 96")
    let expanded = Set([rootID, consoleID, gameID])
    let index = DatabaseFileSidebarTree.Index(items: items)

    #expect(index.rows(expandedFolderIDs: []) == DatabaseFileSidebarTree.rows(items: items, expandedFolderIDs: []))
    #expect(index.rows(expandedFolderIDs: expanded) == DatabaseFileSidebarTree.rows(items: items, expandedFolderIDs: expanded))
}

@MainActor
@Test func databaseFileSidebarPublishesPrebuiltIndex() {
    let rootPath = "/music/Library"
    let item = DatabaseFileItem(
        rootID: 1,
        rootPath: rootPath,
        folderPath: rootPath,
        path: "/music/Library/Actraiser.nsf",
        isArchive: false,
        trackCount: 18
    )
    let sidebar = DatabaseFileSidebarState()
    sidebar.replaceFileItems([item], treeIndex: DatabaseFileSidebarTree.Index(items: [item]))

    let rootID = DatabaseFileSidebarTree.folderID(rootID: 1, path: rootPath)
    #expect(sidebar.rows() == [.folder(id: rootID, title: "Library", depth: 0, isExpanded: false)])
}

@MainActor
@Test func databaseFileSidebarKeepsTheCachedTreeOnAnUnchangedEmptySearch() {
    let rootPath = "/music/Library"
    let item = DatabaseFileItem(
        rootID: 1,
        rootPath: rootPath,
        folderPath: rootPath,
        path: "/music/Library/Actraiser.nsf",
        isArchive: false,
        trackCount: 18
    )
    let sidebar = DatabaseFileSidebarState()
    let secondItem = DatabaseFileItem(
        rootID: 1,
        rootPath: rootPath,
        folderPath: rootPath,
        path: "/music/Library/ChronoTrigger.spc",
        isArchive: false,
        trackCount: 1
    )
    let items = [item, secondItem]
    sidebar.replaceFileItems(items, treeIndex: DatabaseFileSidebarTree.Index(items: items))
    let revision = sidebar.contentRevision

    sidebar.applySearchResult(query: "", items: items, treeIndex: nil)

    #expect(sidebar.contentRevision == revision)
    let rootID = DatabaseFileSidebarTree.folderID(rootID: 1, path: rootPath)
    #expect(sidebar.folder(forID: rootID) == DatabaseFileSidebarFolder(rootID: 1, rootPath: rootPath, path: rootPath))
}

@MainActor
@Test func databaseFileSidebarPublishesBackgroundSearchResult() {
    let rootPath = "/music/Library"
    let matching = DatabaseFileItem(
        rootID: 1,
        rootPath: rootPath,
        folderPath: rootPath,
        path: "/music/Library/Actraiser.nsf",
        isArchive: false,
        trackCount: 18
    )
    let sidebar = DatabaseFileSidebarState()
    sidebar.replaceFileItems([matching], treeIndex: DatabaseFileSidebarTree.Index(items: [matching]))
    sidebar.applySearchResult(
        query: "Act",
        items: [matching],
        treeIndex: DatabaseFileSidebarTree.Index(items: [matching])
    )

    let rootID = DatabaseFileSidebarTree.folderID(rootID: 1, path: rootPath)
    #expect(sidebar.rows() == [
        .folder(id: rootID, title: "Library", depth: 0, isExpanded: true),
        .file(matching, depth: 1)
    ])
}

@MainActor
@Test func databaseFileSidebarRestoresDisclosureStateAfterSearchClears() {
    let rootPath = "/music/Library"
    let item = DatabaseFileItem(
        rootID: 1,
        rootPath: rootPath,
        folderPath: "/music/Library/NES",
        path: "/music/Library/NES/Actraiser.nsf",
        isArchive: false,
        trackCount: 18
    )
    let rootID = DatabaseFileSidebarTree.folderID(rootID: 1, path: rootPath)
    let consoleID = DatabaseFileSidebarTree.folderID(rootID: 1, path: "/music/Library/NES")
    let sidebar = DatabaseFileSidebarState()
    sidebar.replaceFileItems([item], treeIndex: DatabaseFileSidebarTree.Index(items: [item]))
    sidebar.expandedFolderIDs = [rootID]
    sidebar.applySearchResult(
        query: "Act",
        items: [item],
        treeIndex: DatabaseFileSidebarTree.Index(items: [item])
    )
    #expect(sidebar.expandedFolderIDs == [rootID, consoleID])

    sidebar.applySearchResult(query: "", items: [item], treeIndex: nil)
    #expect(sidebar.expandedFolderIDs == [rootID])
}

@Test func databaseFileSidebarFilterCancelsWithoutPublishingPartialResults() {
    let items = [
        DatabaseFileItem(
            rootID: 1,
            rootPath: "/music/Library",
            folderPath: "/music/Library",
            path: "/music/Library/Actraiser.nsf",
            isArchive: false,
            trackCount: 18
        )
    ]
    #expect(DatabaseFileSidebarTree.filter(items, query: "Act", isCancelled: { true }) == nil)
}

@Test func databaseFileSidebarSearchIndexMatchesNormalizedFilter() {
    let items = [
        DatabaseFileItem(
            rootID: 1,
            rootPath: "/music/Library",
            folderPath: "/music/Library/NES",
            path: "/music/Library/NES/Actraiser.nsf",
            isArchive: false,
            trackCount: 18
        ),
        DatabaseFileItem(
            rootID: 1,
            rootPath: "/music/Library",
            folderPath: "/music/Library/SNES",
            path: "/music/Library/SNES/Chrono Trigger.spc",
            isArchive: false,
            trackCount: 64
        )
    ]
    let index = DatabaseFileSidebarTree.SearchIndex(items: items)

    #expect(index.filter(query: "act nes", isCancelled: { false }) == DatabaseFileSidebarTree.filter(items, query: "act nes"))
    #expect(index.filter(query: "chrono", isCancelled: { false }) == DatabaseFileSidebarTree.filter(items, query: "chrono"))
    #expect(index.filter(query: "act", isCancelled: { true }) == nil)
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

@Test func fileSidebarDisclosureUsesPointGapAndChildIndent() {
    let fontSize: CGFloat = 12
    let gap: CGFloat = 6
    let childIndent: CGFloat = 8
    #expect(DatabaseFileSidebarInteraction.indentationStep(fontSize: fontSize, gap: gap) == 17)
    #expect(DatabaseFileSidebarInteraction.titleLeading(depth: 0, fontSize: fontSize, gap: gap, childIndent: childIndent) == 21)
    #expect(DatabaseFileSidebarInteraction.disclosureOrigin(depth: 1, fontSize: fontSize, gap: gap, childIndent: childIndent) == 29)
    #expect(DatabaseFileSidebarInteraction.titleLeading(depth: 0, fontSize: fontSize, gap: gap, childIndent: childIndent) + childIndent == DatabaseFileSidebarInteraction.disclosureOrigin(depth: 1, fontSize: fontSize, gap: gap, childIndent: childIndent))
    #expect(DatabaseFileSidebarInteraction.isDisclosureHit(locationX: 4, depth: 0, fontSize: fontSize, gap: gap, childIndent: childIndent))
    #expect(DatabaseFileSidebarInteraction.isDisclosureHit(locationX: 29, depth: 1, fontSize: fontSize, gap: gap, childIndent: childIndent))
    #expect(!DatabaseFileSidebarInteraction.isDisclosureHit(locationX: 28, depth: 1, fontSize: fontSize, gap: gap, childIndent: childIndent))
    #expect(!DatabaseFileSidebarInteraction.isDisclosureHit(locationX: 40, depth: 1, fontSize: fontSize, gap: gap, childIndent: childIndent))
    #expect(DatabaseFileSidebarInteraction.indentationStep(fontSize: 18, gap: gap) == 23)
    #expect(DatabaseFileSidebarInteraction.childIndentWidth(99) == 32)
}

@MainActor
@Test func databaseSidebarSearchPreservesSelection() {
    let sidebar = DatabaseSidebarState()
    let selected = DatabaseGameItem(rootID: 1, rootPath: "/music/JoshW", name: "Actraiser", systemName: "SNES", trackCount: 18)
    let other = DatabaseGameItem(rootID: 1, rootPath: "/music/JoshW", name: "Mega Man", systemName: "NES", trackCount: 10)
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
    let selected = DatabaseGameItem(rootID: 1, rootPath: "/music/JoshW", name: "Actraiser", systemName: "SNES", trackCount: 18)
    let remaining = DatabaseGameItem(rootID: 1, rootPath: "/music/JoshW", name: "Mega Man", systemName: "NES", trackCount: 10)
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
    defaults.set(true, forKey: AppDefaultsKey.preferEmbeddedConsoleTags)
    defaults.set("search", forKey: AppDefaultsKey.sidebarSearchText)
    defaults.set("/Music", forKey: AppDefaultsKey.lastRootPath)
    defaults.set("/Music/SNES", forKey: AppDefaultsKey.lastLibrarySelectedFolderPath)
    defaults.set(["title", "file"], forKey: AppDefaultsKey.playlistColumnOrder)

    let restored = AppSessionPersistence.restoreSessionState(
        defaults: defaults,
        supportedExtensions: ["spc"]
    )
    #expect(restored?.tracks == [track])
    #expect(restored?.deferredTrackCount == 0)
    #expect(restored?.deferredPersistedValues.isEmpty == true)

    let startup = AppSessionPersistence.restoreStartupState(
        defaults: defaults,
        supportedExtensions: ["spc"]
    )
    #expect(startup.playbackPreferences.longPlayEnabled)
    #expect(startup.playbackPreferences.preferEmbeddedConsoleTags)
    #expect(startup.sessionState?.tracks == [track])
    #expect(startup.playlistColumnState.order == ["title", "file"])
    #expect(startup.sidebarSearchText == "search")
    #expect(startup.lastRootPath == "/Music")
    #expect(startup.lastLibrarySelectedFolderPath == "/Music/SNES")
}

@Test func restoredSessionDefersExcessiveQueueEntries() throws {
    let suiteName = "CocoaSpiceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create isolated UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let trackURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("spc")
    try Data().write(to: trackURL)
    defer { try? FileManager.default.removeItem(at: trackURL) }
    let track = TrackItem(url: trackURL)
    let total = AppSessionPersistence.maximumRestoredPlaylistTracks + 2
    defaults.set(Array(repeating: track.persistedValue, count: total), forKey: AppDefaultsKey.persistedPlaylistPaths)

    let restored = AppSessionPersistence.restoreSessionState(defaults: defaults, supportedExtensions: ["spc"])
    #expect(restored?.tracks.count == AppSessionPersistence.maximumRestoredPlaylistTracks)
    #expect(restored?.deferredTrackCount == 2)
    #expect(restored?.deferredPersistedValues.count == 2)
}

@Test func restoredSessionDoesNotWalkSourcePathsDuringLaunch() {
    let suiteName = "CocoaSpiceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create isolated UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let track = TrackItem(url: URL(fileURLWithPath: "/not-present/Theme.spc"))
    defaults.set([track.persistedValue], forKey: AppDefaultsKey.persistedPlaylistPaths)

    #expect(
        AppSessionPersistence.restoreSessionState(defaults: defaults, supportedExtensions: ["spc"])?.tracks == [track]
    )
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
        supportedExtensions: PlaybackFormatRegistry.supportedExtensions
    )

    #expect(decoded == [original])
}
