import Foundation
import SQLite3

extension LibraryDatabase {
    func searchSidebarItems(query: String, limit: Int = 250) throws -> [SidebarSearchItem] {
        try Self.searchSidebarItems(databaseURL: databaseURL, query: query, limit: limit)
    }

    func loadGameItems(preferFoldersOverMetadata: Bool = true) throws -> [DatabaseGameItem] {
        try Self.loadGameItems(
            databaseURL: databaseURL,
            preferFoldersOverMetadata: preferFoldersOverMetadata
        )
    }

    func loadFileItems() throws -> [DatabaseFileItem] {
        try Self.loadFileItems(databaseURL: databaseURL)
    }

    static func loadGameItems(
        databaseURL: URL,
        preferFoldersOverMetadata: Bool = true
    ) throws -> [DatabaseGameItem] {
        let handle = try openReadOnlyConnection(databaseURL: databaseURL)
        defer { sqlite3_close(handle) }
        return try loadGameItems(handle: handle, preferFoldersOverMetadata: preferFoldersOverMetadata)
    }

    static func loadFileItems(databaseURL: URL) throws -> [DatabaseFileItem] {
        let handle = try openReadOnlyConnection(databaseURL: databaseURL)
        defer { sqlite3_close(handle) }
        return try loadFileItems(handle: handle)
    }

    /// Loads both sidebar modes through one read-only handle so they represent
    /// the same SQLite snapshot and avoid duplicate connection setup.
    static func loadSidebarContent(
        databaseURL: URL,
        preferFoldersOverMetadata: Bool = true
    ) throws -> DatabaseSidebarContent {
        let handle = try openReadOnlyConnection(databaseURL: databaseURL)
        defer { sqlite3_close(handle) }
        return DatabaseSidebarContent(
            gameItems: try loadGameItems(handle: handle, preferFoldersOverMetadata: preferFoldersOverMetadata),
            fileItems: try loadFileItems(handle: handle)
        )
    }

    /// The Games sidebar is the startup browser. Keep its compact grouped
    /// result separate from the potentially very large Files listing.
    static func loadGameSidebarItems(
        databaseURL: URL,
        preferFoldersOverMetadata: Bool = true
    ) throws -> [DatabaseGameItem] {
        let startedAt = Date()
        let handle = try openReadOnlyConnection(databaseURL: databaseURL)
        defer { sqlite3_close(handle) }
        let items = try loadGameItems(handle: handle, preferFoldersOverMetadata: preferFoldersOverMetadata)
        logSlowSidebarRead(name: "Games", itemCount: items.count, startedAt: startedAt)
        return items
    }

    /// File rows are intentionally loaded only when Files mode is shown. A
    /// large collection can have hundreds of thousands of source rows, which
    /// must not delay the initial application window.
    static func loadFileSidebarItems(databaseURL: URL) throws -> [DatabaseFileItem] {
        let startedAt = Date()
        let handle = try openReadOnlyConnection(databaseURL: databaseURL)
        defer { sqlite3_close(handle) }
        let items = try loadFileItems(handle: handle)
        logSlowSidebarRead(name: "Files", itemCount: items.count, startedAt: startedAt)
        return items
    }

    private static func logSlowSidebarRead(name: String, itemCount: Int, startedAt: Date) {
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed >= 0.25 else { return }
        performanceLogger.info("Slow \(name) sidebar read: \(itemCount) items in \(Int((elapsed * 1_000).rounded())) ms")
    }

    private static func loadGameItems(
        handle: OpaquePointer,
        preferFoldersOverMetadata: Bool
    ) throws -> [DatabaseGameItem] {
        // The default folder-first view can use MediaScanner's compact durable
        // projection. Do not regroup the whole catalog when the sidebar opens.
        if preferFoldersOverMetadata,
           try gameSidebarBucketsAreCurrent(handle: handle) {
            return try loadGameItemsFromBuckets(handle: handle)
        }
        // Metadata-first is an optional read-only projection.
        return try loadGameItemsFromTracks(
            handle: handle,
            preferFoldersOverMetadata: preferFoldersOverMetadata
        )
    }

    /// An interrupted or active scan can leave one root's projection dirty.
    /// Preserve exact sidebar results through the direct query rather than
    /// showing a stale game list.
    private static func gameSidebarBucketsAreCurrent(handle: OpaquePointer) throws -> Bool {
        let sql = "SELECT NOT EXISTS (SELECT 1 FROM library_roots WHERE is_enabled = 1 AND game_sidebar_buckets_dirty = 1);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw databaseError(handle: handle)
        }
        return sqlite3_column_int(statement, 0) != 0
    }

    private static func loadGameItemsFromBuckets(handle: OpaquePointer) throws -> [DatabaseGameItem] {
        let sql = """
        SELECT
            b.root_id,
            r.path,
            b.browser_game AS game_name,
            b.browser_system AS system_name,
            b.track_count
        FROM game_sidebar_buckets b
        INNER JOIN library_roots r ON r.id = b.root_id
        WHERE r.is_enabled = 1
        ORDER BY lower(game_name) ASC, game_name ASC, lower(system_name) ASC, system_name ASC, lower(r.path) ASC, r.path ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        var items: [DatabaseGameItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rootID = sqlite3_column_int64(statement, 0)
            let rootPath = sqliteString(statement, index: 1)
            let rawName = sqliteString(statement, index: 2).trimmingCharacters(in: .whitespacesAndNewlines)
            let systemName = sqliteString(statement, index: 3).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName.isEmpty ? "Unknown Game" : rawName
            let displayName = ZipArchiveSupport.canHandle(URL(fileURLWithPath: name))
                ? URL(fileURLWithPath: name).lastPathComponent
                : nil
            let count = Int(sqlite3_column_int(statement, 4))
            items.append(DatabaseGameItem(rootID: rootID, rootPath: rootPath, name: name, systemName: systemName, trackCount: count, displayName: displayName))
        }
        return DatabaseSidebarPresentation.disambiguateGameItems(items)
    }

    private static func loadGameItemsFromTracks(
        handle: OpaquePointer,
        preferFoldersOverMetadata: Bool
    ) throws -> [DatabaseGameItem] {
        let systemName = consoleSystemExpression(preferFoldersOverMetadata: preferFoldersOverMetadata)
        let sql = """
        SELECT
            t.root_id,
            r.path,
            t.browser_game AS game_name,
            \(systemName) AS system_name,
            COUNT(*)
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE r.is_enabled = 1
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
        GROUP BY t.root_id, r.path, game_name, system_name
        ORDER BY lower(game_name) ASC, game_name ASC, lower(system_name) ASC, system_name ASC, lower(r.path) ASC, r.path ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        var items: [DatabaseGameItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rootID = sqlite3_column_int64(statement, 0)
            let rootPath = sqliteString(statement, index: 1)
            let rawName = sqliteString(statement, index: 2).trimmingCharacters(in: .whitespacesAndNewlines)
            let systemName = sqliteString(statement, index: 3).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName.isEmpty ? "Unknown Game" : rawName
            let displayName = ZipArchiveSupport.canHandle(URL(fileURLWithPath: name))
                ? URL(fileURLWithPath: name).lastPathComponent
                : nil
            let count = Int(sqlite3_column_int(statement, 4))
            items.append(DatabaseGameItem(rootID: rootID, rootPath: rootPath, name: name, systemName: systemName, trackCount: count, displayName: displayName))
        }
        return DatabaseSidebarPresentation.disambiguateGameItems(items)
    }

    private static func loadFileItems(handle: OpaquePointer) throws -> [DatabaseFileItem] {
        if try fileSidebarBucketsAreCurrent(handle: handle) {
            return try loadFileItemsFromBuckets(handle: handle)
        }
        return try loadFileItemsFromTracks(handle: handle)
    }

    /// Files must stay exact during an interrupted scan or a maintenance
    /// write. The durable source projection is rebuilt at normal write
    /// boundaries, while this direct grouping is only the dirty-root fallback.
    private static func fileSidebarBucketsAreCurrent(handle: OpaquePointer) throws -> Bool {
        let sql = "SELECT NOT EXISTS (SELECT 1 FROM library_roots WHERE is_enabled = 1 AND file_sidebar_buckets_dirty = 1);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw databaseError(handle: handle)
        }
        return sqlite3_column_int(statement, 0) != 0
    }

    private static func loadFileItemsFromBuckets(handle: OpaquePointer) throws -> [DatabaseFileItem] {
        let sql = """
        SELECT
            b.root_id,
            r.path,
            b.folder_path,
            b.path,
            b.is_archive,
            b.track_count
        FROM file_sidebar_buckets b
        INNER JOIN library_roots r ON r.id = b.root_id
        WHERE r.is_enabled = 1;
        """
        return try readFileItems(handle: handle, sql: sql)
    }

    private static func loadFileItemsFromTracks(handle: OpaquePointer) throws -> [DatabaseFileItem] {
        let sql = """
        SELECT
            t.root_id,
            r.path,
            t.folder_path,
            t.path,
            MAX(t.archive_path IS NOT NULL),
            COUNT(*)
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        WHERE r.is_enabled = 1
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
        GROUP BY t.root_id, r.path, t.folder_path, t.path
        ;
        """

        return try readFileItems(handle: handle, sql: sql)
    }

    private static func readFileItems(handle: OpaquePointer, sql: String) throws -> [DatabaseFileItem] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }
        var items: [DatabaseFileItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(DatabaseFileItem(
                rootID: sqlite3_column_int64(statement, 0),
                rootPath: sqliteString(statement, index: 1),
                folderPath: sqliteString(statement, index: 2),
                path: sqliteString(statement, index: 3),
                isArchive: sqlite3_column_int(statement, 4) != 0,
                trackCount: Int(sqlite3_column_int(statement, 5))
            ))
        }
        return items
    }

    private static func openReadOnlyConnection(databaseURL: URL) throws -> OpaquePointer {
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard let handle else {
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open the database."])
        }
        return handle
    }

    func tracksForGame(
        _ gameItem: DatabaseGameItem,
        preferFoldersOverMetadata: Bool = true
    ) throws -> [TrackItem] {
        try Self.tracksForGame(
            databaseURL: databaseURL,
            gameItem: gameItem,
            preferFoldersOverMetadata: preferFoldersOverMetadata
        )
    }

    func tracksAndMetadataForGames(
        _ gameItems: [DatabaseGameItem],
        preferFoldersOverMetadata: Bool = true
    ) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        try Self.tracksAndMetadataForGames(
            databaseURL: databaseURL,
            gameItems: gameItems,
            preferFoldersOverMetadata: preferFoldersOverMetadata
        )
    }

    func tracksAndMetadataForFiles(_ fileItems: [DatabaseFileItem]) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        try Self.tracksAndMetadataForFiles(databaseURL: databaseURL, fileItems: fileItems)
    }

    func tracksAndMetadataForFolder(rootPath: String, folderPath: String) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        try Self.tracksAndMetadataForFolder(databaseURL: databaseURL, rootPath: rootPath, folderPath: folderPath)
    }

    func tracksAndMetadataForPaths(_ paths: [String]) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        try Self.tracksAndMetadataForPaths(databaseURL: databaseURL, paths: paths)
    }

    static func tracksForGame(
        databaseURL: URL,
        gameItem: DatabaseGameItem,
        preferFoldersOverMetadata: Bool = true
    ) throws -> [TrackItem] {
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let message = Self.databaseError(handle: handle).localizedDescription
            sqlite3_close(handle)
            throw NSError(domain: "LibraryDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let systemPredicate = consoleSystemPredicate(preferFoldersOverMetadata: preferFoldersOverMetadata)
        let sql = """
        SELECT t.path, t.archive_path, t.archive_entry, t.track_index, t.track_count
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE r.is_enabled = 1
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
          AND t.root_id = ?
          AND t.browser_game = ?
          AND \(systemPredicate)
        ORDER BY t.folder_path ASC, t.filename ASC, t.track_index ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        sqliteBind(.int(gameItem.rootID), to: statement, at: 1)
        sqliteBind(.text(gameItem.name), to: statement, at: 2)
        sqliteBind(.text(gameItem.systemName), to: statement, at: 3)

        var tracks: [TrackItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            tracks.append(
                track(from: statement, pathIndex: 0, archivePathIndex: 1, archiveEntryIndex: 2, trackIndex: 3, trackCount: 4)
            )
        }
        return tracks
    }

    static func tracksAndMetadataForGames(
        databaseURL: URL,
        gameItems: [DatabaseGameItem],
        preferFoldersOverMetadata: Bool = true
    ) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
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

        let systemPredicate = consoleSystemPredicate(preferFoldersOverMetadata: preferFoldersOverMetadata)
        let bucketPredicate = Array(
            repeating: "(t.root_id = ? AND t.browser_game = ? AND \(systemPredicate))",
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
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
          AND (\(bucketPredicate))
        ORDER BY t.browser_game ASC, lower(COALESCE(m.title, '')) ASC, t.folder_path ASC, t.filename ASC, t.track_index ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(handle: handle)
        }
        defer { sqlite3_finalize(statement) }

        for (index, gameItem) in normalizedItems.enumerated() {
            let baseIndex = index * 3
            sqliteBind(.int(gameItem.rootID), to: statement, at: Int32(baseIndex + 1))
            sqliteBind(.text(gameItem.name), to: statement, at: Int32(baseIndex + 2))
            sqliteBind(.text(gameItem.systemName), to: statement, at: Int32(baseIndex + 3))
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

    private static func consoleSystemExpression(preferFoldersOverMetadata: Bool) -> String {
        preferFoldersOverMetadata
            ? "COALESCE(NULLIF(t.browser_system, ''), NULLIF(m.system, ''), '')"
            : "COALESCE(NULLIF(m.system, ''), NULLIF(t.browser_system, ''), '')"
    }

    private static func consoleSystemPredicate(preferFoldersOverMetadata: Bool) -> String {
        preferFoldersOverMetadata
            ? "t.browser_system = ?"
            : "\(consoleSystemExpression(preferFoldersOverMetadata: false)) = ?"
    }

    static func tracksAndMetadataForFiles(databaseURL: URL, fileItems: [DatabaseFileItem]) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        let normalizedItems = Array(NSOrderedSet(array: fileItems)) as? [DatabaseFileItem] ?? []
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

        let sourcePredicate = Array(
            repeating: "(t.root_id = ? AND t.path = ?)",
            count: normalizedItems.count
        ).joined(separator: " OR ")
        // A Path-sidebar activation identifies exact scanned sources. Force
        // the root/path lookup index so SQLite does not scan a complete root
        // merely to satisfy the folder-oriented sort order.
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
        FROM tracks t INDEXED BY tracks_source_lookup_index
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE r.is_enabled = 1
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
          AND (\(sourcePredicate))
        ORDER BY t.folder_path ASC, t.filename ASC, t.track_index ASC;
        """

        let bindings = normalizedItems.flatMap { [SQLiteValue.int($0.rootID), SQLiteValue.text($0.path)] }
        return try readTracksAndMetadata(handle: handle, sql: sql, bindings: bindings)
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
        let folderPrefix = normalizedFolderPath.hasSuffix("/")
            ? normalizedFolderPath
            : normalizedFolderPath + "/"
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
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
          AND r.path = ?
          AND (t.folder_path = ? OR t.folder_path LIKE ?)
        ORDER BY t.filename ASC, t.track_index ASC;
        """

        return try readTracksAndMetadata(
            handle: handle,
            sql: sql,
            bindings: [.text(normalizedRootPath), .text(normalizedFolderPath), .text(folderPrefix + "%")]
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
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
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
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
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
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
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
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
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
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
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
          AND NOT EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id = t.root_id AND d.path = t.path)
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

        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
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
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else { throw databaseError(handle: handle) }

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
