import Foundation
import SQLite3
import Testing
@testable import CocoaSpice

@Test func gameSidebarBucketsServeCleanRootsAndDirtyRootsFallBackToTracks() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-game-sidebar-buckets-\(UUID().uuidString)", isDirectory: true)
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

    func result(path: String, game: String, system: String) -> ScanPipelineResult {
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
                            song: "Theme",
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

    let firstPath = directory.appendingPathComponent("first.spc").path
    let secondPath = directory.appendingPathComponent("second.spc").path
    try database.persistScanTrackResults([
        result(path: firstPath, game: "Game", system: "SNES"),
        result(path: secondPath, game: "Other", system: "Game Boy")
    ])

    // A dirty root remains correct through the direct query until its durable
    // projection is refreshed at scan completion.
    #expect(try database.loadGameItems().count == 2)
    try database.markScanCompleted(rootID: root.id)
    #expect(try gameBucketCount(database: database, rootID: root.id) == 2)

    try database.markSourcesDead([
        LibraryIndexedSource(rootID: root.id, path: firstPath, archiveEntry: nil)
    ])
    #expect(try database.loadGameItems() == [
        DatabaseGameItem(rootID: root.id, rootPath: directory.path, name: "Other", systemName: "Game Boy", trackCount: 1)
    ])

    try database.markScanCompleted(rootID: root.id)
    #expect(try gameBucketCount(database: database, rootID: root.id) == 1)
}

@Test func gameSidebarKeepsSameGameAndSystemSeparatePerLibraryRoot() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-root-scoped-games-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let firstRootPath = directory.appendingPathComponent("JoshW", isDirectory: true).path
    let secondRootPath = directory.appendingPathComponent("SNESMusicOrg", isDirectory: true).path
    try FileManager.default.createDirectory(atPath: firstRootPath, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: secondRootPath, withIntermediateDirectories: true)

    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"))
    try database.addRoot(path: firstRootPath)
    try database.addRoot(path: secondRootPath)
    let rootsByPath = Dictionary(uniqueKeysWithValues: try database.loadRoots().map { ($0.path, $0) })
    let firstRoot = try #require(rootsByPath[firstRootPath])
    let secondRoot = try #require(rootsByPath[secondRootPath])
    let route = ScanRoute(pluginID: "gme", formatExtension: "spc", supportsArchiveMembers: true, supportsMultiTrack: false)
    let timestamp = Date(timeIntervalSince1970: 1)

    func result(root: LibraryScanRoot, path: String, song: String) -> ScanPipelineResult {
        let candidate = ScanCandidate(
            identity: ScanItemIdentity(rootID: root.id, path: path, archiveEntry: nil),
            fingerprint: ScanFingerprint(fileSize: 1, modifiedAt: timestamp),
            sourceURL: URL(fileURLWithPath: path),
            route: route
        )
        return .success(candidate, ScanInspection(
            route: route,
            tracks: [ScanTrackMetadata(
                trackIndex: 0,
                trackCount: 1,
                metadata: TrackMetadata(
                    game: "Final Fight",
                    song: song,
                    system: "SNES",
                    author: "",
                    comment: "",
                    introLengthMs: 0,
                    loopLengthMs: 0,
                    playLengthMs: 60_000,
                    fadeLengthMs: 0
                )
            )]
        ))
    }

    let firstPath = firstRootPath + "/Final Fight.spc"
    let secondPath = secondRootPath + "/Final Fight.spc"
    try database.persistScanTrackResults([
        result(root: firstRoot, path: firstPath, song: "Josh Theme"),
        result(root: secondRoot, path: secondPath, song: "SMO Theme")
    ])
    try database.markScanCompleted(rootID: firstRoot.id)
    try database.markScanCompleted(rootID: secondRoot.id)

    let items = try database.loadGameItems().filter { $0.name == "Final Fight" }
    #expect(items.count == 2)
    #expect(Set(items.map(\.id)).count == 2)
    #expect(Set(items.map(\.displayName)) == [
        "Final Fight (SNES • JoshW)",
        "Final Fight (SNES • SNESMusicOrg)"
    ])

    let firstLoaded = try database.tracksAndMetadataForGames([try #require(items.first { $0.rootID == firstRoot.id })])
    let secondLoaded = try database.tracksAndMetadataForGames([try #require(items.first { $0.rootID == secondRoot.id })])
    #expect(firstLoaded.tracks.map(\.url.path) == [firstPath])
    #expect(secondLoaded.tracks.map(\.url.path) == [secondPath])
}

@Test func fileSidebarBucketsServeStoredSourceLeavesAndDirtyRootFallbacks() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-file-sidebar-buckets-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"))
    try database.addRoot(path: directory.path)
    let root = try #require(database.loadRoots().first)
    let path = directory.appendingPathComponent("Soundtrack.nsf").path
    let route = ScanRoute(pluginID: "gme", formatExtension: "nsf", supportsArchiveMembers: true, supportsMultiTrack: true)
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: root.id, path: path, archiveEntry: nil),
        fingerprint: ScanFingerprint(fileSize: 1, modifiedAt: Date(timeIntervalSince1970: 1)),
        sourceURL: URL(fileURLWithPath: path),
        route: route
    )
    let metadata = TrackMetadata(
        game: "Game",
        song: "Theme",
        system: "NES",
        author: "",
        comment: "",
        introLengthMs: 0,
        loopLengthMs: 0,
        playLengthMs: 60_000,
        fadeLengthMs: 0
    )
    let inspection = ScanInspection(
        route: route,
        tracks: [
            ScanTrackMetadata(trackIndex: 0, trackCount: 2, metadata: metadata),
            ScanTrackMetadata(trackIndex: 1, trackCount: 2, metadata: metadata)
        ]
    )
    try database.persistScanTrackResults([.success(candidate, inspection)])
    try database.markScanCompleted(rootID: root.id)

    #expect(try database.loadFileItems() == [
        DatabaseFileItem(
            rootID: root.id,
            rootPath: directory.path,
            folderPath: directory.path,
            path: path,
            isArchive: false,
            trackCount: 2
        )
    ])
    #expect(try fileSidebarBucketCount(database: database, rootID: root.id) == 1)

    try database.markSourcesDead([LibraryIndexedSource(rootID: root.id, path: path, archiveEntry: nil)])
    #expect(try database.loadFileItems().isEmpty)

    try database.markScanCompleted(rootID: root.id)
    #expect(try fileSidebarBucketCount(database: database, rootID: root.id) == 0)
}

@MainActor
@Test func databaseSidebarLoaderRetainsFilesUntilExplicitInvalidation() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-sidebar-loader-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"))
    try database.addRoot(path: directory.path)
    let root = try #require(database.loadRoots().first)
    let path = directory.appendingPathComponent("Theme.spc").path
    let route = ScanRoute(pluginID: "gme", formatExtension: "spc", supportsArchiveMembers: true, supportsMultiTrack: false)
    let candidate = ScanCandidate(
        identity: ScanItemIdentity(rootID: root.id, path: path, archiveEntry: nil),
        fingerprint: ScanFingerprint(fileSize: 1, modifiedAt: Date(timeIntervalSince1970: 1)),
        sourceURL: URL(fileURLWithPath: path),
        route: route
    )
    try database.persistScanTrackResults([.success(candidate, ScanInspection(
        route: route,
        tracks: [ScanTrackMetadata(
            trackIndex: 0,
            trackCount: 1,
            metadata: TrackMetadata(
                game: "Game",
                song: "Theme",
                system: "SNES",
                author: "",
                comment: "",
                introLengthMs: 0,
                loopLengthMs: 0,
                playLengthMs: 60_000,
                fadeLengthMs: 0
            )
        )]
    ))])
    try database.markScanCompleted(rootID: root.id)

    let games = DatabaseSidebarState()
    let files = DatabaseFileSidebarState()
    let loader = DatabaseSidebarLoader(gameSidebar: games, fileSidebar: files)
    var fileLoadCount = 0

    await withCheckedContinuation { continuation in
        loader.loadIfNeeded(
            databaseURL: database.databaseURL,
            mode: .files,
            didLoadGames: {},
            didLoadFiles: {
                fileLoadCount += 1
                continuation.resume()
            }
        )
    }
    #expect(files.fileItems.count == 1)
    #expect(loader.hasLoadedFiles)
    #expect(!loader.isLoadingFiles)
    #expect(loader.fileLoadingStatus.isEmpty)
    let initialRevision = files.contentRevision

    loader.loadIfNeeded(
        databaseURL: database.databaseURL,
        mode: .files,
        didLoadGames: {},
        didLoadFiles: { fileLoadCount += 1 }
    )
    #expect(fileLoadCount == 1)
    #expect(files.contentRevision == initialRevision)

    await withCheckedContinuation { continuation in
        loader.invalidateAndLoad(
            databaseURL: database.databaseURL,
            mode: .files,
            didLoadGames: {},
            didLoadFiles: {
                fileLoadCount += 1
                continuation.resume()
            }
        )
    }
    #expect(fileLoadCount == 2)
    #expect(files.contentRevision > initialRevision)
}

private func gameBucketCount(database: LibraryDatabase, rootID: Int64) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database.db,
        "SELECT COALESCE(SUM(track_count), 0) FROM game_sidebar_buckets WHERE root_id = ?;",
        -1,
        &statement,
        nil
    ) == SQLITE_OK else {
        throw database.databaseError()
    }
    defer { sqlite3_finalize(statement) }
    sqliteBind(.int(rootID), to: statement, at: 1)
    guard sqlite3_step(statement) == SQLITE_ROW else { throw database.databaseError() }
    return Int(sqlite3_column_int(statement, 0))
}

private func fileSidebarBucketCount(database: LibraryDatabase, rootID: Int64) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database.db,
        "SELECT COUNT(*) FROM file_sidebar_buckets WHERE root_id = ?;",
        -1,
        &statement,
        nil
    ) == SQLITE_OK else {
        throw database.databaseError()
    }
    defer { sqlite3_finalize(statement) }
    sqliteBind(.int(rootID), to: statement, at: 1)
    guard sqlite3_step(statement) == SQLITE_ROW else { throw database.databaseError() }
    return Int(sqlite3_column_int(statement, 0))
}

@Test func outdatedDatabaseIsRebuiltAsTheCurrentSchema() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-game-sidebar-migration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("Library.sqlite")

    var handle: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &handle) == SQLITE_OK)
    defer { sqlite3_close(handle) }
    try executeSQLite(handle, """
    CREATE TABLE obsolete_library_table (id INTEGER PRIMARY KEY, value TEXT);
    INSERT INTO obsolete_library_table VALUES (1, 'stale');
    PRAGMA user_version = 14;
    """)
    sqlite3_close(handle)
    handle = nil

    let database = try LibraryDatabase(databaseURL: databaseURL)
    #expect(try database.loadRoots().isEmpty)
    #expect(try database.loadGameItems().isEmpty)
}

private func executeSQLite(_ database: OpaquePointer?, _ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
        defer { sqlite3_free(error) }
        throw NSError(
            domain: "LibraryGameSidebarBucketTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: error.map { String(cString: $0) } ?? "SQLite command failed"]
        )
    }
}
