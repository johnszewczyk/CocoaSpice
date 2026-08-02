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
        DatabaseGameItem(name: "Other", systemName: "Game Boy", trackCount: 1)
    ])

    try database.markScanCompleted(rootID: root.id)
    #expect(try gameBucketCount(database: database, rootID: root.id) == 1)
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

@Test func gameSidebarBucketMigrationPrewarmsExistingVersionThirteenLibrary() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-game-sidebar-migration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("Library.sqlite")

    var handle: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &handle) == SQLITE_OK)
    defer { sqlite3_close(handle) }
    try executeSQLite(handle, """
    CREATE TABLE library_roots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        display_order INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL,
        last_scan_started_at REAL,
        last_scan_completed_at REAL,
        last_scan_track_count INTEGER NOT NULL DEFAULT 0,
        last_scan_error TEXT,
        is_attached INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        root_id INTEGER NOT NULL,
        folder_path TEXT NOT NULL,
        path TEXT NOT NULL,
        filename TEXT NOT NULL,
        extension TEXT NOT NULL,
        browser_game TEXT NOT NULL DEFAULT '',
        browser_system TEXT NOT NULL DEFAULT '',
        track_index INTEGER NOT NULL DEFAULT 0,
        track_count INTEGER NOT NULL DEFAULT 1,
        file_size INTEGER NOT NULL,
        modified_at REAL NOT NULL,
        discovered_at REAL NOT NULL,
        archive_path TEXT,
        archive_entry TEXT,
        UNIQUE(root_id, path, archive_entry, track_index)
    );
    CREATE TABLE dead_sources (
        root_id INTEGER NOT NULL,
        path TEXT NOT NULL,
        marked_at REAL NOT NULL,
        PRIMARY KEY(root_id, path)
    );
    INSERT INTO library_roots (id, path, is_enabled, display_order, created_at)
    VALUES (1, '/Music', 1, 0, 0);
    INSERT INTO tracks (root_id, folder_path, path, filename, extension, browser_game, browser_system, track_index, track_count, file_size, modified_at, discovered_at)
    VALUES (1, '/Music/Game', '/Music/Game/theme.spc', 'theme.spc', 'spc', 'Game', 'SNES', 0, 1, 1, 0, 0);
    PRAGMA user_version = 13;
    """)
    sqlite3_close(handle)
    handle = nil

    let database = try LibraryDatabase(databaseURL: databaseURL)
    try LibraryDatabase.prepareGameSidebarIndex(databaseURL: databaseURL)

    #expect(try database.loadGameItems() == [
        DatabaseGameItem(name: "Game", systemName: "SNES", trackCount: 1)
    ])
    #expect(try gameBucketCount(database: database, rootID: 1) == 1)
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
