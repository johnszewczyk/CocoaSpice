import Foundation
import SQLite3

final class LibraryDatabase: @unchecked Sendable {
    static let schemaVersion = 14
    let db: OpaquePointer?
    private let dbURL: URL

    var databaseURL: URL { dbURL }

    convenience init() throws {
        let supportURL = try Self.applicationSupportDirectory()
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let dbURL = supportURL.appendingPathComponent("Library.sqlite", isDirectory: false)
        let legacyURL = supportURL
            .deletingLastPathComponent()
            .appendingPathComponent("SPCBoy", isDirectory: true)
            .appendingPathComponent("Library.sqlite", isDirectory: false)
        if FileManager.default.fileExists(atPath: legacyURL.path),
           !Self.databaseHasRoots(at: dbURL),
           Self.databaseHasRoots(at: legacyURL) {
            if FileManager.default.fileExists(atPath: dbURL.path) {
                try FileManager.default.removeItem(at: dbURL)
            }
            try FileManager.default.moveItem(at: legacyURL, to: dbURL)
        }
        try self.init(databaseURL: dbURL)
    }

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dbURL = databaseURL.standardizedFileURL
        self.dbURL = dbURL

        var handle: OpaquePointer?
        if sqlite3_open(dbURL.path, &handle) != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        db = handle
        sqlite3_extended_result_codes(handle, 1)
        try execute("PRAGMA foreign_keys = ON;")
        // The scan writes many short transactions while sidebar readers may
        // still hold a statement. Wait for that ordinary contention instead
        // of misreporting a healthy member as a persistence failure.
        sqlite3_busy_timeout(handle, 5_000)
        try execute("""
        CREATE TABLE IF NOT EXISTS library_roots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL UNIQUE,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            display_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            last_scan_started_at REAL,
            last_scan_completed_at REAL,
            last_scan_track_count INTEGER NOT NULL DEFAULT 0,
            last_scan_error TEXT
        );
        """)
        try migrateSchemaIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    func loadScanInventory(rootID: Int64) throws -> [ScanInventoryItem] {
        let sql = """
        SELECT path, archive_entry, file_size, modified_at, content_signature, state, plugin_id, format_extension, supports_archive_members, supports_multi_track
        FROM scan_items
        WHERE root_id = ?
        ORDER BY path ASC, archive_entry ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        sqliteBind(.int(rootID), to: statement, at: 1)

        var items: [ScanInventoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let entry = sqliteNullableString(statement, index: 1)
            let pluginID = sqliteNullableString(statement, index: 6)
            let route = pluginID.map {
                ScanRoute(
                    pluginID: $0,
                    formatExtension: sqliteString(statement, index: 7),
                    supportsArchiveMembers: sqlite3_column_int(statement, 8) != 0,
                    supportsMultiTrack: sqlite3_column_int(statement, 9) != 0
                )
            }
            items.append(
                ScanInventoryItem(
                    identity: ScanItemIdentity(
                        rootID: rootID,
                        path: sqliteString(statement, index: 0),
                        archiveEntry: entry?.isEmpty == false ? entry : nil
                    ),
                    fingerprint: ScanFingerprint(
                        fileSize: sqlite3_column_int64(statement, 2),
                        modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                        contentSignature: sqliteNullableString(statement, index: 4)
                    ),
                    state: ScanItemState(rawValue: sqliteString(statement, index: 5)) ?? .discovered,
                    route: route
                )
            )
        }
        return items
    }

    func scanCompletedWithoutIssues(rootID: Int64) throws -> Bool {
        let sql = """
        SELECT COUNT(*), SUM(CASE WHEN state IN ('failed', 'unsupported') THEN 1 ELSE 0 END)
        FROM scan_items WHERE root_id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        sqliteBind(.int(rootID), to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return sqlite3_column_int(statement, 0) > 0 && sqlite3_column_int(statement, 1) == 0
    }

    func scanResultTally(rootID: Int64) throws -> (successful: Int, total: Int) {
        let sql = """
        SELECT
            SUM(CASE WHEN state = 'successful' THEN 1 ELSE 0 END),
            COUNT(*)
        FROM scan_items
        WHERE root_id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        sqliteBind(.int(rootID), to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return (Int(sqlite3_column_int(statement, 0)), Int(sqlite3_column_int(statement, 1)))
    }

    func upsertScanItem(
        _ item: ScanInventoryItem,
        failure: ScanFailure? = nil
    ) throws {
        try execute(
            """
            INSERT INTO scan_items (root_id, path, archive_entry, file_size, modified_at, content_signature, state, plugin_id, format_extension, supports_archive_members, supports_multi_track, failure_stage, failure_message, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(root_id, path, archive_entry) DO UPDATE SET
                file_size = excluded.file_size,
                modified_at = excluded.modified_at,
                content_signature = excluded.content_signature,
                state = excluded.state,
                plugin_id = excluded.plugin_id,
                format_extension = excluded.format_extension,
                supports_archive_members = excluded.supports_archive_members,
                supports_multi_track = excluded.supports_multi_track,
                failure_stage = excluded.failure_stage,
                failure_message = excluded.failure_message,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .int(item.identity.rootID),
                .text(item.identity.path),
                .text(item.identity.archiveEntry ?? ""),
                .int(item.fingerprint.fileSize),
                .double(item.fingerprint.modifiedAt.timeIntervalSince1970),
                item.fingerprint.contentSignature.map(SQLiteValue.text) ?? .null,
                .text(item.state.rawValue),
                item.route.map { .text($0.pluginID) } ?? .null,
                item.route.map { .text($0.formatExtension) } ?? .null,
                .int(item.route?.supportsArchiveMembers == true ? 1 : 0),
                .int(item.route?.supportsMultiTrack == true ? 1 : 0),
                failure.map { .text($0.stage.rawValue) } ?? .null,
                failure.map { .text($0.message) } ?? .null,
                .double(Date().timeIntervalSince1970)
            ]
        )
    }

    func refreshScanFingerprint(
        identity: ScanItemIdentity,
        fingerprint: ScanFingerprint
    ) throws {
        try execute(
            """
            UPDATE scan_items
            SET file_size = ?, modified_at = ?, content_signature = ?, updated_at = ?
            WHERE root_id = ? AND path = ? AND archive_entry = ?;
            """,
            bindings: [
                .int(fingerprint.fileSize),
                .double(fingerprint.modifiedAt.timeIntervalSince1970),
                fingerprint.contentSignature.map(SQLiteValue.text) ?? .null,
                .double(Date().timeIntervalSince1970),
                .int(identity.rootID),
                .text(identity.path),
                .text(identity.archiveEntry ?? "")
            ]
        )
    }

    func clearScanInventory(rootID: Int64) throws {
        try execute("DELETE FROM scan_items WHERE root_id = ?;", bindings: [.int(rootID)])
    }

    func clearTracks(rootID: Int64) throws {
        try execute("DELETE FROM tracks WHERE root_id = ?;", bindings: [.int(rootID)])
        try markGameSidebarBucketsDirty(rootIDs: [rootID])
    }

    func clearLiveScanInventory(rootID: Int64) throws {
        try execute("""
        DELETE FROM scan_items
        WHERE root_id = ?
          AND NOT EXISTS (
              SELECT 1 FROM dead_sources d
              WHERE d.root_id = scan_items.root_id AND d.path = scan_items.path
          );
        """, bindings: [.int(rootID)])
    }

    func clearLiveTracks(rootID: Int64) throws {
        try execute("""
        DELETE FROM tracks
        WHERE root_id = ?
          AND NOT EXISTS (
              SELECT 1 FROM dead_sources d
              WHERE d.root_id = tracks.root_id AND d.path = tracks.path
          );
        """, bindings: [.int(rootID)])
        try markGameSidebarBucketsDirty(rootIDs: [rootID])
    }

    func purgeIndexedLibrary() throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute("DELETE FROM tracks;")
            try execute("DELETE FROM scan_items;")
            try execute("DELETE FROM dead_sources;")
            try execute("DELETE FROM game_sidebar_buckets;")
            try execute("DELETE FROM library_roots WHERE is_attached = 0;")
            try execute("""
            UPDATE library_roots
            SET last_scan_started_at = NULL,
                last_scan_completed_at = NULL,
                last_scan_track_count = 0,
                last_scan_error = NULL,
                game_sidebar_buckets_dirty = 0;
            """)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func indexedSources() throws -> [LibraryIndexedSource] {
        let sql = """
        SELECT DISTINCT root_id, path
        FROM tracks
        WHERE NOT EXISTS (
            SELECT 1 FROM dead_sources d
            WHERE d.root_id = tracks.root_id AND d.path = tracks.path
        )
        ORDER BY path ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(statement) }

        var sources: [LibraryIndexedSource] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            sources.append(LibraryIndexedSource(
                rootID: sqlite3_column_int64(statement, 0),
                path: sqliteString(statement, index: 1),
                archiveEntry: nil
            ))
        }
        return sources
    }

    func markSourcesDead(_ sources: [LibraryIndexedSource]) throws {
        guard !sources.isEmpty else { return }
        try execute("BEGIN TRANSACTION;")
        do {
            let rootIDs = Set(sources.map(\.rootID))
            for source in sources {
                try execute(
                    """
                    INSERT INTO dead_sources (root_id, path, marked_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(root_id, path) DO UPDATE SET marked_at = excluded.marked_at;
                    """,
                    bindings: [.int(source.rootID), .text(source.path), .double(Date().timeIntervalSince1970)]
                )
            }
            for rootID in rootIDs {
                try execute(
                    """
                    UPDATE library_roots SET last_scan_track_count = (
                        SELECT COUNT(*) FROM tracks t
                        WHERE t.root_id = ?
                          AND NOT EXISTS (
                              SELECT 1 FROM dead_sources d
                              WHERE d.root_id = t.root_id AND d.path = t.path
                          )
                    )
                    WHERE id = ?;
                    """,
                    bindings: [.int(rootID), .int(rootID)]
                )
            }
            try markGameSidebarBucketsDirty(rootIDs: rootIDs)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func restoreSources(_ sources: [LibraryIndexedSource]) throws {
        guard !sources.isEmpty else { return }
        try execute("BEGIN TRANSACTION;")
        do {
            var restoredRootIDs = Set<Int64>()
            for source in Set(sources) {
                try execute(
                    "DELETE FROM dead_sources WHERE root_id = ? AND path = ?;",
                    bindings: [.int(source.rootID), .text(source.path)]
                )
                if sqlite3_changes(db) > 0 {
                    restoredRootIDs.insert(source.rootID)
                }
            }
            try markGameSidebarBucketsDirty(rootIDs: restoredRootIDs)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func deadSourceCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM dead_sources;")
    }

    func trackCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM tracks;")
    }

    func deadTrackCount() throws -> Int {
        try scalarInt("""
        SELECT COUNT(*)
        FROM dead_sources d
        INNER JOIN tracks t ON t.root_id = d.root_id AND t.path = d.path;
        """)
    }

    func deleteDeadSources() throws -> Int {
        let count = try deadSourceCount()
        guard count > 0 else { return 0 }
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute("""
            DELETE FROM tracks
            WHERE EXISTS (
                SELECT 1 FROM dead_sources d
                WHERE d.root_id = tracks.root_id AND d.path = tracks.path
            );
            """)
            try execute("""
            DELETE FROM scan_items
            WHERE EXISTS (
                SELECT 1 FROM dead_sources d
                WHERE d.root_id = scan_items.root_id AND d.path = scan_items.path
            );
            """)
            try execute("DELETE FROM dead_sources;")
            try execute("""
            UPDATE library_roots
            SET last_scan_track_count = (SELECT COUNT(*) FROM tracks WHERE tracks.root_id = library_roots.id);
            """)
            try execute("COMMIT;")
            return count
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func persistScanTrackResults(
        _ results: [ScanPipelineResult]
    ) throws {
        try execute("BEGIN TRANSACTION;")
        do {
            try persistScanTrackResultsInCurrentTransaction(
                results
            )
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    /// Starts an archive refresh with no surviving member rows. Archive tools
    /// are allowed to normalize member paths differently after a repack (for
    /// example, adding a leading `./`), so replacing members one-by-one can
    /// otherwise leave obsolete tracks and metadata visible in the library.
    func resetArchiveMembers(rootID: Int64, path: String) throws {
        try execute("BEGIN TRANSACTION;")
        do {
            try execute(
                "DELETE FROM tracks WHERE root_id = ? AND path = ? AND archive_entry IS NOT NULL;",
                bindings: [.int(rootID), .text(path)]
            )
            try execute(
                "DELETE FROM scan_items WHERE root_id = ? AND path = ? AND archive_entry <> '';",
                bindings: [.int(rootID), .text(path)]
            )
            try markGameSidebarBucketsDirty(rootIDs: [rootID])
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func persistScanResults(
        _ results: [ScanPipelineResult]
    ) throws {
        guard !results.isEmpty else { return }
        try execute("BEGIN TRANSACTION;")
        do {
            for result in results {
                try persistScanResult(result)
            }
            try persistScanTrackResultsInCurrentTransaction(
                results
            )
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func persistScanTrackResultsInCurrentTransaction(
        _ results: [ScanPipelineResult]
    ) throws {
        let successes = results.compactMap { result -> (ScanCandidate, ScanInspection)? in
            guard case .success(let candidate, let inspection) = result else { return nil }
            return (candidate, inspection)
        }
        guard !successes.isEmpty else { return }

        let touchedRootIDs = Set(successes.map { $0.0.identity.rootID })

        for (candidate, inspection) in successes {
            if let archiveEntry = candidate.identity.archiveEntry {
                try execute(
                    "DELETE FROM tracks WHERE root_id = ? AND path = ? AND archive_entry = ?;",
                    bindings: [.int(candidate.identity.rootID), .text(candidate.identity.path), .text(archiveEntry)]
                )
            } else {
                try execute(
                    "DELETE FROM tracks WHERE root_id = ? AND path = ? AND archive_entry IS NULL;",
                    bindings: [.int(candidate.identity.rootID), .text(candidate.identity.path)]
                )
            }

            for track in inspection.tracks {
                let path = candidate.identity.path
                let folderPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
                let filename = candidate.identity.archiveEntry.map {
                    URL(fileURLWithPath: $0).lastPathComponent
                } ?? URL(fileURLWithPath: path).lastPathComponent
                let extensionName = inspection.route.formatExtension
                let archivePath = candidate.identity.archiveEntry == nil ? nil : path
                let metadata = track.metadata
                let browserGame = metadata?.game.trimmingCharacters(in: .whitespacesAndNewlines)
                let browserSystem = metadata?.system.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolvedBrowserGame = browserGame.flatMap { $0.isEmpty ? nil : $0 }
                    ?? archivePath
                    ?? folderPath
                try execute(
                    """
                    INSERT INTO tracks (root_id, folder_path, path, filename, extension, browser_game, browser_system, track_index, track_count, file_size, modified_at, discovered_at, archive_path, archive_entry)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .int(candidate.identity.rootID),
                        .text(folderPath),
                        .text(path),
                        .text(filename),
                        .text(extensionName),
                        .text(resolvedBrowserGame),
                        .text(browserSystem),
                        .int(Int64(track.trackIndex)),
                        .int(Int64(track.trackCount)),
                        .int(candidate.fingerprint.fileSize),
                        .double(candidate.fingerprint.modifiedAt.timeIntervalSince1970),
                        .double(Date().timeIntervalSince1970),
                        archivePath.map(SQLiteValue.text) ?? .null,
                        candidate.identity.archiveEntry.map(SQLiteValue.text) ?? .null
                    ]
                )
                guard let metadata else { continue }
                let trackID = try lastInsertedRowID()
                try execute(
                    """
                    INSERT INTO track_metadata (track_id, title, game, author, system, comment, intro_length_ms, loop_length_ms, play_length_ms, fade_length_ms, metadata_scanned_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .int(trackID),
                        .text(metadata.song),
                        .text(metadata.game),
                        .text(metadata.author),
                        .text(metadata.system),
                        .text(metadata.comment),
                        .int(Int64(metadata.introLengthMs)),
                        .int(Int64(metadata.loopLengthMs)),
                        .int(Int64(metadata.playLengthMs)),
                        .int(Int64(metadata.fadeLengthMs)),
                        .double(Date().timeIntervalSince1970)
                    ]
                )
            }
        }
        try markGameSidebarBucketsDirty(rootIDs: touchedRootIDs)
    }

    func markScanFailed(rootID: Int64, error: String) throws {
        try execute(
            "UPDATE library_roots SET last_scan_completed_at = ?, last_scan_error = ? WHERE id = ?;",
            bindings: [.double(Date().timeIntervalSince1970), .text(error), .int(rootID)]
        )
    }


    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            sqliteBind(binding, to: statement, at: Int32(index + 1))
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func lastInsertedRowID() throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT last_insert_rowid();", -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return sqlite3_column_int64(statement, 0)
    }

    func databaseError() -> NSError {
        Self.databaseError(handle: db)
    }


    func string(_ statement: OpaquePointer?, index: Int32) -> String {
        sqliteString(statement, index: index)
    }

    func nullableString(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    func date(_ statement: OpaquePointer?, index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("CocoaSpice", isDirectory: true)
    }

    static func databaseError(handle: OpaquePointer?) -> NSError {
        let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
        let extendedCode = handle.map { sqlite3_extended_errcode($0) } ?? SQLITE_ERROR
        return NSError(
            domain: "LibraryDatabase",
            code: Int(extendedCode),
            userInfo: [NSLocalizedDescriptionKey: "\(message) (SQLite extended code \(extendedCode))"]
        )
    }

    private static func databaseHasRoots(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return false
        }
        defer { sqlite3_close(handle) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT 1 FROM library_roots LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }
}


enum SQLiteValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func sqliteBind(_ value: SQLiteValue, to statement: OpaquePointer?, at index: Int32) {
    switch value {
    case let .int(number):
        sqlite3_bind_int64(statement, index, number)
    case let .double(number):
        sqlite3_bind_double(statement, index, number)
    case let .text(string):
        sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
    case .null:
        sqlite3_bind_null(statement, index)
    }
}

func sqliteString(_ statement: OpaquePointer?, index: Int32) -> String {
    String(cString: sqlite3_column_text(statement, index))
}

func sqliteNullableString(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
}
