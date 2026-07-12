import Foundation
import SQLite3

final class LibraryDatabase {
    private static let schemaVersion = 5
    private let db: OpaquePointer?
    private let dbURL: URL

    var databaseURL: URL { dbURL }

    init() throws {
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
        self.dbURL = dbURL

        var handle: OpaquePointer?
        if sqlite3_open(dbURL.path, &handle) != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        db = handle
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

    func loadRoots() throws -> [LibraryScanRoot] {
        let sql = """
        SELECT id, path, is_enabled, display_order, last_scan_started_at, last_scan_completed_at, last_scan_track_count, last_scan_error
        FROM library_roots
        ORDER BY lower(path) ASC, path ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }

        var roots: [LibraryScanRoot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            roots.append(
                LibraryScanRoot(
                    id: sqlite3_column_int64(statement, 0),
                    path: string(statement, index: 1),
                    isEnabled: sqlite3_column_int(statement, 2) != 0,
                    displayOrder: Int(sqlite3_column_int(statement, 3)),
                    lastScanStartedAt: date(statement, index: 4),
                    lastScanCompletedAt: date(statement, index: 5),
                    lastScanTrackCount: Int(sqlite3_column_int(statement, 6)),
                    lastScanError: nullableString(statement, index: 7)
                )
            )
        }
        return roots
    }

    func addRoot(path: String) throws {
        let now = Date().timeIntervalSince1970
        let nextOrder = try loadRoots().count
        try execute(
            """
            INSERT INTO library_roots (path, is_enabled, display_order, created_at)
            VALUES (?, 1, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                is_enabled = 1,
                path = excluded.path;
            """,
            bindings: [
                .text(path),
                .int(Int64(nextOrder)),
                .double(now)
            ]
        )
    }

    func setRootEnabled(id: Int64, isEnabled: Bool) throws {
        try execute(
            "UPDATE library_roots SET is_enabled = ? WHERE id = ?;",
            bindings: [.int(isEnabled ? 1 : 0), .int(id)]
        )
    }

    func deleteRoot(id: Int64) throws {
        try execute("DELETE FROM library_roots WHERE id = ?;", bindings: [.int(id)])
    }

    func updateRootOrder(idsInOrder: [Int64]) throws {
        for (index, id) in idsInOrder.enumerated() {
            try execute(
                "UPDATE library_roots SET display_order = ? WHERE id = ?;",
                bindings: [.int(Int64(index)), .int(id)]
            )
        }
    }

    func markScanStarted(rootID: Int64) throws {
        try execute(
            "UPDATE library_roots SET last_scan_started_at = ?, last_scan_error = NULL WHERE id = ?;",
            bindings: [.double(Date().timeIntervalSince1970), .int(rootID)]
        )
    }

    func markScanCompleted(rootID: Int64, trackCount: Int) throws {
        try execute(
            "UPDATE library_roots SET last_scan_completed_at = ?, last_scan_track_count = ?, last_scan_error = NULL WHERE id = ?;",
            bindings: [.double(Date().timeIntervalSince1970), .int(Int64(trackCount)), .int(rootID)]
        )
    }

    func loadScanInventory(rootID: Int64) throws -> [ScanInventoryItem] {
        let sql = """
        SELECT path, archive_entry, file_size, modified_at, state, plugin_id, format_extension, supports_archive_members, supports_multi_track
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
            let pluginID = sqliteNullableString(statement, index: 5)
            let route = pluginID.map {
                ScanRoute(
                    pluginID: $0,
                    formatExtension: sqliteString(statement, index: 6),
                    supportsArchiveMembers: sqlite3_column_int(statement, 7) != 0,
                    supportsMultiTrack: sqlite3_column_int(statement, 8) != 0
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
                        modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                    ),
                    state: ScanItemState(rawValue: sqliteString(statement, index: 4)) ?? .discovered,
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

    func upsertScanItem(
        _ item: ScanInventoryItem,
        failure: ScanFailure? = nil
    ) throws {
        try execute(
            """
            INSERT INTO scan_items (root_id, path, archive_entry, file_size, modified_at, state, plugin_id, format_extension, supports_archive_members, supports_multi_track, failure_stage, failure_message, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(root_id, path, archive_entry) DO UPDATE SET
                file_size = excluded.file_size,
                modified_at = excluded.modified_at,
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

    func clearScanInventory(rootID: Int64) throws {
        try execute("DELETE FROM scan_items WHERE root_id = ?;", bindings: [.int(rootID)])
    }

    func clearTracks(rootID: Int64) throws {
        try execute("DELETE FROM tracks WHERE root_id = ?;", bindings: [.int(rootID)])
    }

    func indexedSources() throws -> [LibraryIndexedSource] {
        let sql = """
        SELECT DISTINCT root_id, path
        FROM tracks
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

    func trimMissingPaths(_ sources: [LibraryIndexedSource]) throws {
        guard !sources.isEmpty else { return }
        try execute("BEGIN TRANSACTION;")
        do {
            for source in sources {
                try execute("DELETE FROM tracks WHERE root_id = ? AND path = ?;", bindings: [.int(source.rootID), .text(source.path)])
                try execute("DELETE FROM scan_items WHERE root_id = ? AND path = ?;", bindings: [.int(source.rootID), .text(source.path)])
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func persistScanTrackResults(_ results: [ScanPipelineResult]) throws {
        let successes = results.compactMap { result -> (ScanCandidate, ScanInspection)? in
            guard case .success(let candidate, let inspection) = result else { return nil }
            return (candidate, inspection)
        }
        guard !successes.isEmpty else { return }

        try execute("BEGIN TRANSACTION;")
        do {
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
                    let filename = candidate.identity.archiveEntry.map {
                        URL(fileURLWithPath: $0).lastPathComponent
                    } ?? URL(fileURLWithPath: path).lastPathComponent
                    let extensionName = inspection.route.formatExtension
                    let archivePath = candidate.identity.archiveEntry == nil ? nil : path
                    try execute(
                        """
                        INSERT INTO tracks (root_id, folder_path, path, filename, extension, track_index, track_count, file_size, modified_at, discovered_at, archive_path, archive_entry)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                        """,
                        bindings: [
                            .int(candidate.identity.rootID),
                            .text(URL(fileURLWithPath: path).deletingLastPathComponent().path),
                            .text(path),
                            .text(filename),
                            .text(extensionName),
                            .int(Int64(track.trackIndex)),
                            .int(Int64(track.trackCount)),
                            .int(candidate.fingerprint.fileSize),
                            .double(candidate.fingerprint.modifiedAt.timeIntervalSince1970),
                            .double(Date().timeIntervalSince1970),
                            archivePath.map(SQLiteValue.text) ?? .null,
                            candidate.identity.archiveEntry.map(SQLiteValue.text) ?? .null
                        ]
                    )
                    guard let metadata = track.metadata else { continue }
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
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func markScanFailed(rootID: Int64, error: String) throws {
        try execute(
            "UPDATE library_roots SET last_scan_completed_at = ?, last_scan_error = ? WHERE id = ?;",
            bindings: [.double(Date().timeIntervalSince1970), .text(error), .int(rootID)]
        )
    }

    func searchSidebarItems(query: String, limit: Int = 250) throws -> [SidebarSearchItem] {
        try Self.searchSidebarItems(databaseURL: dbURL, query: query, limit: limit)
    }

    func loadGameItems() throws -> [DatabaseGameItem] {
        try Self.loadGameItems(databaseURL: dbURL)
    }

    static func loadGameItems(databaseURL: URL) throws -> [DatabaseGameItem] {
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let sql = """
        SELECT
            CASE
                WHEN trim(COALESCE(m.game, '')) <> '' THEN trim(m.game)
                ELSE COALESCE(t.archive_path, t.folder_path)
            END AS game_name,
            trim(COALESCE(m.system, '')) AS system_name,
            COUNT(*)
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE r.is_enabled = 1
        GROUP BY game_name, system_name
        ORDER BY lower(game_name) ASC, game_name ASC, lower(system_name) ASC, system_name ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        var items: [DatabaseGameItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rawName = sqliteString(statement, index: 0).trimmingCharacters(in: .whitespacesAndNewlines)
            let systemName = sqliteString(statement, index: 1).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName.isEmpty ? "Unknown Game" : rawName
            let displayName = ZipArchiveSupport.canHandle(URL(fileURLWithPath: name))
                ? URL(fileURLWithPath: name).lastPathComponent
                : nil
            let count = Int(sqlite3_column_int(statement, 2))
            items.append(DatabaseGameItem(name: name, systemName: systemName, trackCount: count, displayName: displayName))
        }
        return DatabaseSidebarPresentation.disambiguateGameItems(items)
    }

    func tracksForGame(_ gameItem: DatabaseGameItem) throws -> [TrackItem] {
        try Self.tracksForGame(databaseURL: dbURL, gameItem: gameItem)
    }

    func tracksAndMetadataForGames(_ gameItems: [DatabaseGameItem]) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        try Self.tracksAndMetadataForGames(databaseURL: dbURL, gameItems: gameItems)
    }

    func tracksAndMetadataForFolder(rootPath: String, folderPath: String) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        try Self.tracksAndMetadataForFolder(databaseURL: dbURL, rootPath: rootPath, folderPath: folderPath)
    }

    func tracksAndMetadataForPaths(_ paths: [String]) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        try Self.tracksAndMetadataForPaths(databaseURL: dbURL, paths: paths)
    }

    static func tracksForGame(databaseURL: URL, gameItem: DatabaseGameItem) throws -> [TrackItem] {
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let sql = """
        SELECT t.path, t.archive_path, t.archive_entry, t.track_index, t.track_count
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE r.is_enabled = 1
          AND CASE
                WHEN trim(COALESCE(m.game, '')) <> '' THEN trim(m.game)
                ELSE COALESCE(t.archive_path, t.folder_path)
              END = ?
          AND trim(COALESCE(m.system, '')) = ?
        ORDER BY lower(COALESCE(m.title, '')) ASC, t.folder_path ASC, t.filename ASC, t.track_index ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        sqliteBind(.text(gameItem.name), to: statement, at: 1)
        sqliteBind(.text(gameItem.systemName), to: statement, at: 2)

        var tracks: [TrackItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            tracks.append(
                track(from: statement, pathIndex: 0, archivePathIndex: 1, archiveEntryIndex: 2, trackIndex: 3, trackCount: 4)
            )
        }
        return tracks
    }

    static func tracksAndMetadataForGames(databaseURL: URL, gameItems: [DatabaseGameItem]) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        let normalizedItems = Array(NSOrderedSet(array: gameItems)) as? [DatabaseGameItem] ?? []
        guard !normalizedItems.isEmpty else {
            return ([], [:], PlaylistColumnWidthHints(indexText: "1", fileText: "", titleText: "", gameText: "", authorText: "", systemText: "", lengthText: "—"))
        }

        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let bucketPredicate = Array(
            repeating: """
            (
                CASE
                    WHEN trim(COALESCE(m.game, '')) <> '' THEN trim(m.game)
                    ELSE COALESCE(t.archive_path, t.folder_path)
                END = ?
                AND trim(COALESCE(m.system, '')) = ?
            )
            """,
            count: normalizedItems.count
        ).joined(separator: " OR ")
        let sql = """
        SELECT
            t.path,
            t.archive_path,
            t.archive_entry,
            t.track_index,
            t.track_count,
            COALESCE(m.title, ''),
            COALESCE(m.game, ''),
            COALESCE(m.author, ''),
            COALESCE(m.system, ''),
            COALESCE(m.comment, ''),
            COALESCE(m.intro_length_ms, 0),
            COALESCE(m.loop_length_ms, 0),
            COALESCE(m.play_length_ms, 0),
            COALESCE(m.fade_length_ms, 0)
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE r.is_enabled = 1
          AND (\(bucketPredicate))
        ORDER BY lower(COALESCE(m.game, '')) ASC, lower(COALESCE(m.title, '')) ASC, t.folder_path ASC, t.filename ASC, t.track_index ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        for (index, gameItem) in normalizedItems.enumerated() {
            let baseIndex = index * 2
            sqliteBind(.text(gameItem.name), to: statement, at: Int32(baseIndex + 1))
            sqliteBind(.text(gameItem.systemName), to: statement, at: Int32(baseIndex + 2))
        }

        var tracks: [TrackItem] = []
        var metadata: [String: TrackMetadata] = [:]
        var widestFileText = ""
        var widestTitleText = ""
        var widestGameText = ""
        var widestAuthorText = ""
        var widestSystemText = ""
        var widestLengthText = "—"
        while sqlite3_step(statement) == SQLITE_ROW {
            let track = track(from: statement, pathIndex: 0, archivePathIndex: 1, archiveEntryIndex: 2, trackIndex: 3, trackCount: 4)
            let title = sqliteString(statement, index: 5)
            let game = sqliteString(statement, index: 6)
            let author = sqliteString(statement, index: 7)
            let system = sqliteString(statement, index: 8)
            let comment = sqliteString(statement, index: 9)
            let introLengthMs = Int(sqlite3_column_int(statement, 10))
            let loopLengthMs = Int(sqlite3_column_int(statement, 11))
            let playLengthMs = Int(sqlite3_column_int(statement, 12))
            let fadeLengthMs = Int(sqlite3_column_int(statement, 13))
            tracks.append(track)
            metadata[track.id] = TrackMetadata(
                game: game,
                song: title,
                system: system,
                author: author,
                comment: comment,
                introLengthMs: introLengthMs,
                loopLengthMs: loopLengthMs,
                playLengthMs: playLengthMs,
                fadeLengthMs: fadeLengthMs
            )

            widestFileText = widerText(widestFileText, track.filename)
            widestTitleText = widerText(widestTitleText, title.isEmpty ? track.displayName : title)
            widestGameText = widerText(widestGameText, game.isEmpty ? track.url.deletingLastPathComponent().lastPathComponent : game)
            widestAuthorText = widerText(widestAuthorText, author.isEmpty ? "—" : author)
            widestSystemText = widerText(widestSystemText, system.isEmpty ? "SNES" : system)
            let lengthText = formatLengthText(playLengthMs: playLengthMs)
            widestLengthText = widerText(widestLengthText, lengthText)
        }

        let widthHints = PlaylistColumnWidthHints(
            indexText: String(max(1, tracks.count)),
            fileText: widestFileText,
            titleText: widestTitleText,
            gameText: widestGameText,
            authorText: widestAuthorText,
            systemText: widestSystemText,
            lengthText: widestLengthText
        )

        return (tracks, metadata, widthHints)
    }

    static func tracksAndMetadataForFolder(databaseURL: URL, rootPath: String, folderPath: String) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let normalizedRootPath = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let normalizedFolderPath = URL(fileURLWithPath: folderPath, isDirectory: true).standardizedFileURL.path
        let sql = """
        SELECT
            t.path,
            t.archive_path,
            t.archive_entry,
            t.track_index,
            t.track_count,
            COALESCE(m.title, ''),
            COALESCE(m.game, ''),
            COALESCE(m.author, ''),
            COALESCE(m.system, ''),
            COALESCE(m.comment, ''),
            COALESCE(m.intro_length_ms, 0),
            COALESCE(m.loop_length_ms, 0),
            COALESCE(m.play_length_ms, 0),
            COALESCE(m.fade_length_ms, 0)
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE r.is_enabled = 1
          AND r.path = ?
          AND t.folder_path = ?
        ORDER BY t.filename ASC, t.track_index ASC;
        """

        return try readTracksAndMetadata(
            handle: handle,
            sql: sql,
            bindings: [.text(normalizedRootPath), .text(normalizedFolderPath)]
        )
    }

    static func tracksAndMetadataForPaths(databaseURL: URL, paths: [String]) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        let normalizedPaths = Array(NSOrderedSet(array: paths.map {
            URL(fileURLWithPath: $0, isDirectory: false).standardizedFileURL.path
        })) as? [String] ?? []
        guard !normalizedPaths.isEmpty else {
            return ([], [:], PlaylistColumnWidthHints(indexText: "1", fileText: "", titleText: "", gameText: "", authorText: "", systemText: "", lengthText: "—"))
        }

        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let placeholders = Array(repeating: "?", count: normalizedPaths.count).joined(separator: ", ")
        let sql = """
        SELECT
            t.path,
            t.archive_path,
            t.archive_entry,
            t.track_index,
            t.track_count,
            COALESCE(m.title, ''),
            COALESCE(m.game, ''),
            COALESCE(m.author, ''),
            COALESCE(m.system, ''),
            COALESCE(m.comment, ''),
            COALESCE(m.intro_length_ms, 0),
            COALESCE(m.loop_length_ms, 0),
            COALESCE(m.play_length_ms, 0),
            COALESCE(m.fade_length_ms, 0)
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE r.is_enabled = 1
          AND t.path IN (\(placeholders))
        ORDER BY t.filename ASC, t.track_index ASC;
        """

        return try readTracksAndMetadata(
            handle: handle,
            sql: sql,
            bindings: normalizedPaths.map(SQLiteValue.text)
        )
    }

    static func searchFolderPaths(databaseURL: URL, query: String, limit: Int = 500) throws -> Set<String> {
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        let folderConditions = terms.map { _ in "lower(t.folder_path) LIKE ?" }.joined(separator: " AND ")
        let sql = """
        SELECT DISTINCT t.folder_path
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        WHERE r.is_enabled = 1
          AND \(folderConditions)
        ORDER BY t.folder_path ASC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        for term in terms {
            sqliteBind(.text("%\(term)%"), to: statement, at: bindIndex)
            bindIndex += 1
        }
        sqliteBind(.int(Int64(limit)), to: statement, at: bindIndex)

        var paths = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            paths.insert(sqliteString(statement, index: 0))
        }
        return paths
    }

    static func childFolders(databaseURL: URL, rootPath: String, parentPath: String) throws -> [URL] {
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let normalizedRootPath = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let normalizedParentPath = URL(fileURLWithPath: parentPath, isDirectory: true).standardizedFileURL.path
        let prefix = normalizedParentPath.hasSuffix("/") ? normalizedParentPath : normalizedParentPath + "/"
        let sql = """
        SELECT DISTINCT t.folder_path
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        WHERE r.is_enabled = 1
          AND r.path = ?
          AND (t.folder_path = ? OR t.folder_path LIKE ?)
        ORDER BY t.folder_path ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        sqliteBind(.text(normalizedRootPath), to: statement, at: 1)
        sqliteBind(.text(normalizedParentPath), to: statement, at: 2)
        sqliteBind(.text(prefix + "%"), to: statement, at: 3)

        var childPaths = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            let folderPath = sqliteString(statement, index: 0)
            guard folderPath.hasPrefix(prefix), folderPath != normalizedParentPath else { continue }
            let suffix = String(folderPath.dropFirst(prefix.count))
            guard let firstComponent = suffix.split(separator: "/").first, !firstComponent.isEmpty else { continue }
            let childPath = URL(fileURLWithPath: normalizedParentPath, isDirectory: true)
                .appendingPathComponent(String(firstComponent), isDirectory: true)
                .standardizedFileURL
                .path
            childPaths.insert(childPath)
        }

        return childPaths
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func files(inFolder databaseURL: URL, rootPath: String, folderPath: String) throws -> [URL] {
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let normalizedRootPath = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let normalizedFolderPath = URL(fileURLWithPath: folderPath, isDirectory: true).standardizedFileURL.path
        let sql = """
        SELECT DISTINCT t.path
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        WHERE r.is_enabled = 1
          AND r.path = ?
          AND t.folder_path = ?
        ORDER BY t.filename ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        sqliteBind(.text(normalizedRootPath), to: statement, at: 1)
        sqliteBind(.text(normalizedFolderPath), to: statement, at: 2)

        var files: [URL] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            files.append(URL(fileURLWithPath: sqliteString(statement, index: 0), isDirectory: false))
        }
        return files
    }

    static func searchSidebarItems(databaseURL: URL, query: String, limit: Int = 250) throws -> [SidebarSearchItem] {
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        return try searchSidebarItems(handle: handle, query: query, limit: limit)
    }

    private static func searchSidebarItems(handle db: OpaquePointer?, query: String, limit: Int) throws -> [SidebarSearchItem] {
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        let folderConditions = terms.map { _ in "lower(t.folder_path) LIKE ?" }.joined(separator: " AND ")
        let fileConditions = terms.map { _ in """
        (
            lower(t.filename) LIKE ?
            OR lower(COALESCE(m.title, '')) LIKE ?
            OR lower(COALESCE(m.game, '')) LIKE ?
            OR lower(COALESCE(m.author, '')) LIKE ?
            OR lower(COALESCE(m.system, '')) LIKE ?
            OR lower(t.folder_path) LIKE ?
        )
        """ }.joined(separator: " AND ")

        let folderSQL = """
        SELECT DISTINCT t.folder_path, r.path
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        WHERE r.is_enabled = 1
          AND \(folderConditions)
        ORDER BY t.folder_path ASC
        LIMIT ?;
        """

        let fileSQL = """
        SELECT
            t.path,
            t.archive_path,
            t.archive_entry,
            t.track_index,
            t.track_count,
            COALESCE(m.title, ''),
            COALESCE(m.game, ''),
            r.path
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE r.is_enabled = 1
          AND \(fileConditions)
        ORDER BY t.folder_path ASC, t.filename ASC, t.track_index ASC
        LIMIT ?;
        """

        var items: [SidebarSearchItem] = []

        var folderStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, folderSQL, -1, &folderStatement, nil) == SQLITE_OK else {
            throw databaseError(handle: db)
        }
        defer { sqlite3_finalize(folderStatement) }

        var bindIndex: Int32 = 1
        for term in terms {
            sqliteBind(.text("%\(term)%"), to: folderStatement, at: bindIndex)
            bindIndex += 1
        }
        sqliteBind(.int(Int64(limit)), to: folderStatement, at: bindIndex)

        while sqlite3_step(folderStatement) == SQLITE_ROW {
            let path = sqliteString(folderStatement, index: 0)
            let rootPath = sqliteString(folderStatement, index: 1)
            items.append(
                SidebarSearchItem(
                    url: URL(fileURLWithPath: path, isDirectory: true),
                    kind: .folder,
                    secondaryTextOverride: displayContextPath(path: path, rootPath: rootPath)
                )
            )
        }

        var fileStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, fileSQL, -1, &fileStatement, nil) == SQLITE_OK else {
            throw databaseError(handle: db)
        }
        defer { sqlite3_finalize(fileStatement) }

        bindIndex = 1
        for term in terms {
            let wildcard = "%\(term)%"
            for _ in 0..<6 {
                sqliteBind(.text(wildcard), to: fileStatement, at: bindIndex)
                bindIndex += 1
            }
        }
        sqliteBind(.int(Int64(limit)), to: fileStatement, at: bindIndex)

        while sqlite3_step(fileStatement) == SQLITE_ROW {
            let path = sqliteString(fileStatement, index: 0)
            let title = sqliteNullableString(fileStatement, index: 5)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let game = sqliteNullableString(fileStatement, index: 6)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rootPath = sqliteString(fileStatement, index: 7)
            let track = track(from: fileStatement, pathIndex: 0, archivePathIndex: 1, archiveEntryIndex: 2, trackIndex: 3, trackCount: 4)
            items.append(
                SidebarSearchItem(
                    url: track.url,
                    kind: .track,
                    track: track,
                    primaryTextOverride: title?.isEmpty == false ? title : track.displayName,
                    secondaryTextOverride: game?.isEmpty == false ? game : displayContextPath(path: path, rootPath: rootPath)
                )
            )
        }

        return items
    }

    private func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
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

    private func lastInsertedRowID() throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT last_insert_rowid();", -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return sqlite3_column_int64(statement, 0)
    }

    private func databaseError() -> NSError {
        Self.databaseError(handle: db)
    }

    private static func readTracksAndMetadata(
        handle: OpaquePointer?,
        sql: String,
        bindings: [SQLiteValue]
    ) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            sqliteBind(binding, to: statement, at: Int32(index + 1))
        }

        var tracks: [TrackItem] = []
        var metadata: [String: TrackMetadata] = [:]
        var widestFileText = ""
        var widestTitleText = ""
        var widestGameText = ""
        var widestAuthorText = ""
        var widestSystemText = ""
        var widestLengthText = "—"

        while sqlite3_step(statement) == SQLITE_ROW {
            let track = track(from: statement, pathIndex: 0, archivePathIndex: 1, archiveEntryIndex: 2, trackIndex: 3, trackCount: 4)
            let title = sqliteString(statement, index: 5)
            let game = sqliteString(statement, index: 6)
            let author = sqliteString(statement, index: 7)
            let system = sqliteString(statement, index: 8)
            let comment = sqliteString(statement, index: 9)
            let introLengthMs = Int(sqlite3_column_int(statement, 10))
            let loopLengthMs = Int(sqlite3_column_int(statement, 11))
            let playLengthMs = Int(sqlite3_column_int(statement, 12))
            let fadeLengthMs = Int(sqlite3_column_int(statement, 13))

            tracks.append(track)
            metadata[track.id] = TrackMetadata(
                game: game,
                song: title,
                system: system,
                author: author,
                comment: comment,
                introLengthMs: introLengthMs,
                loopLengthMs: loopLengthMs,
                playLengthMs: playLengthMs,
                fadeLengthMs: fadeLengthMs
            )

            widestFileText = widerText(widestFileText, track.filename)
            widestTitleText = widerText(widestTitleText, title.isEmpty ? track.displayName : title)
            widestGameText = widerText(widestGameText, game.isEmpty ? track.url.deletingLastPathComponent().lastPathComponent : game)
            widestAuthorText = widerText(widestAuthorText, author.isEmpty ? "—" : author)
            widestSystemText = widerText(widestSystemText, system.isEmpty ? "SNES" : system)
            let lengthText = formatLengthText(playLengthMs: playLengthMs)
            widestLengthText = widerText(widestLengthText, lengthText)
        }

        let widthHints = PlaylistColumnWidthHints(
            indexText: String(max(1, tracks.count)),
            fileText: widestFileText,
            titleText: widestTitleText,
            gameText: widestGameText,
            authorText: widestAuthorText,
            systemText: widestSystemText,
            lengthText: widestLengthText
        )
        return (tracks, metadata, widthHints)
    }

    private static func track(
        from statement: OpaquePointer?,
        pathIndex: Int32,
        archivePathIndex: Int32,
        archiveEntryIndex: Int32,
        trackIndex: Int32,
        trackCount: Int32
    ) -> TrackItem {
        let path = sqliteString(statement, index: pathIndex)
        let index = Int(sqlite3_column_int(statement, trackIndex))
        let count = Int(sqlite3_column_int(statement, trackCount))
        if let archivePath = sqliteNullableString(statement, index: archivePathIndex),
           let archiveEntry = sqliteNullableString(statement, index: archiveEntryIndex),
           !archivePath.isEmpty,
           !archiveEntry.isEmpty {
            return TrackItem(
                archiveURL: URL(fileURLWithPath: archivePath, isDirectory: false),
                entryPath: archiveEntry,
                trackIndex: index,
                trackCount: count
            )
        }
        return TrackItem(
            url: URL(fileURLWithPath: path, isDirectory: false),
            trackIndex: index,
            trackCount: count
        )
    }

    private func migrateSchemaIfNeeded() throws {
        let version = try userVersion()
        if version < 4 {
            try execute("DROP TABLE IF EXISTS track_metadata;")
            try execute("DROP TABLE IF EXISTS tracks;")
            try createTrackTables()
        }
        if version < 5 {
            try createScanTables()
        }
        guard version < Self.schemaVersion else { return }
        try setUserVersion(Self.schemaVersion)
    }

    private func createTrackTables() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            root_id INTEGER NOT NULL,
            folder_path TEXT NOT NULL,
            path TEXT NOT NULL,
            filename TEXT NOT NULL,
            extension TEXT NOT NULL,
            track_index INTEGER NOT NULL DEFAULT 0,
            track_count INTEGER NOT NULL DEFAULT 1,
            file_size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            discovered_at REAL NOT NULL,
            archive_path TEXT,
            archive_entry TEXT,
            UNIQUE(path, archive_entry, track_index),
            FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS track_metadata (
            track_id INTEGER PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '',
            game TEXT NOT NULL DEFAULT '',
            author TEXT NOT NULL DEFAULT '',
            system TEXT NOT NULL DEFAULT '',
            comment TEXT NOT NULL DEFAULT '',
            intro_length_ms INTEGER NOT NULL DEFAULT 0,
            loop_length_ms INTEGER NOT NULL DEFAULT 0,
            play_length_ms INTEGER NOT NULL DEFAULT 0,
            fade_length_ms INTEGER NOT NULL DEFAULT 0,
            metadata_scanned_at REAL NOT NULL,
            FOREIGN KEY(track_id) REFERENCES tracks(id) ON DELETE CASCADE
        );
        """)
    }

    private func createScanTables() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS scan_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            root_id INTEGER NOT NULL,
            path TEXT NOT NULL,
            archive_entry TEXT NOT NULL DEFAULT '',
            file_size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            state TEXT NOT NULL,
            plugin_id TEXT,
            format_extension TEXT,
            supports_archive_members INTEGER NOT NULL DEFAULT 0,
            supports_multi_track INTEGER NOT NULL DEFAULT 0,
            failure_stage TEXT,
            failure_message TEXT,
            updated_at REAL NOT NULL,
            UNIQUE(root_id, path, archive_entry),
            FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS scan_items_state_index ON scan_items(root_id, state);")
    }

    private func userVersion() throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw databaseError()
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version);")
    }

    private func string(_ statement: OpaquePointer?, index: Int32) -> String {
        sqliteString(statement, index: index)
    }

    private func nullableString(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func date(_ statement: OpaquePointer?, index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("CocoaSpice", isDirectory: true)
    }

    private static func databaseError(handle: OpaquePointer?) -> NSError {
        let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
        return NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
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

private func displayContextPath(path: String, rootPath: String) -> String {
    let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
    let itemURL = URL(fileURLWithPath: path, isDirectory: true)
    let itemParent = itemURL.deletingLastPathComponent()
    let rootName = rootURL.lastPathComponent

    guard itemParent.path.hasPrefix(rootURL.path) else {
        return itemParent.path
    }

    let relative = String(itemParent.path.dropFirst(rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if relative.isEmpty {
        return rootName
    }
    return "\(rootName)/\(relative)"
}

private func widerText(_ lhs: String, _ rhs: String) -> String {
    rhs.count > lhs.count ? rhs : lhs
}

private func formatLengthText(playLengthMs: Int) -> String {
    let seconds = max(0, playLengthMs > 0 ? playLengthMs / 1000 : 0)
    guard seconds > 0 else { return "—" }
    let minutes = seconds / 60
    let remainder = seconds % 60
    return String(format: "%d:%02d", minutes, remainder)
}

private enum SQLiteValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func sqliteBind(_ value: SQLiteValue, to statement: OpaquePointer?, at index: Int32) {
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

private func sqliteString(_ statement: OpaquePointer?, index: Int32) -> String {
    String(cString: sqlite3_column_text(statement, index))
}

private func sqliteNullableString(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
}
