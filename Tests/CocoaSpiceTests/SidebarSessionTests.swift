import AppKit
import C2SF
import Foundation
import Testing
@testable import CocoaSpice

// Retain historic test names while production code uses the neutral registry.
private typealias GMEFormatSupport = PlaybackFormatRegistry

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
        .folder(id: rootID, title: "Library", depth: 0, isExpanded: false)
    ])
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
    #expect(restored?.deferredTrackCount == 0)
    #expect(restored?.deferredPersistedValues.isEmpty == true)

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
