import Foundation
import MediaScannerKit
import SQLite3

extension LibraryDatabase {
    func rewriteSidebarIdentity(preferEmbeddedMetadata: Bool) throws {
        let sql = """
        SELECT t.id, t.root_id, t.path, t.archive_entry, t.extension,
               r.path, COALESCE(m.game, ''), COALESCE(m.system, '')
        FROM tracks t
        INNER JOIN library_roots r ON r.id = t.root_id
        LEFT JOIN track_metadata m ON m.track_id = t.id
        WHERE t.id > ?
        ORDER BY t.id
        LIMIT 5000;
        """
        let updateStatement = try prepareStatement(
            "UPDATE tracks SET browser_game = ?, browser_system = ? WHERE id = ?;"
        )
        defer { sqlite3_finalize(updateStatement) }
        var lastTrackID: Int64 = 0
        var touchedRootIDs = Set<Int64>()
        try withSavepoint {
            while true {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw databaseError()
                }
                guard let statement else { throw databaseError() }
                sqliteBind(.int(lastTrackID), to: statement, at: 1)
                var updates: [(id: Int64, rootID: Int64, game: String, system: String)] = []
                var stepResult = sqlite3_step(statement)
                while stepResult == SQLITE_ROW {
                    let id = sqlite3_column_int64(statement, 0)
                    let rootID = sqlite3_column_int64(statement, 1)
                    let sourcePath = sqliteString(statement, index: 2)
                    let archiveEntry = sqlite3_column_type(statement, 3) == SQLITE_NULL
                        ? nil
                        : sqliteString(statement, index: 3)
                    let extensionName = sqliteString(statement, index: 4)
                    let rootPath = sqliteString(statement, index: 5)
                    let metadataGame = sqliteString(statement, index: 6)
                    let metadataSystem = sqliteString(statement, index: 7)
                    let route = BuiltInScannerPlugins.registry.route(
                        for: extensionName,
                        archiveMember: archiveEntry != nil
                    )
                    updates.append((
                        id,
                        rootID,
                        LibraryConsoleResolver.browserGame(
                            metadataGame: metadataGame,
                            sourcePath: sourcePath,
                            archiveEntry: archiveEntry
                        ),
                        LibraryConsoleResolver.browserSystem(
                            metadataSystem: metadataSystem,
                            route: route,
                            sourcePath: sourcePath,
                            rootPath: rootPath,
                            preferEmbeddedMetadata: preferEmbeddedMetadata
                        )
                    ))
                    stepResult = sqlite3_step(statement)
                }
                sqlite3_finalize(statement)
                guard stepResult == SQLITE_DONE else { throw databaseError() }
                guard !updates.isEmpty else { break }
                for update in updates {
                    try executePrepared(
                        updateStatement,
                        bindings: [.text(update.game), .text(update.system), .int(update.id)]
                    )
                    touchedRootIDs.insert(update.rootID)
                    lastTrackID = update.id
                }
            }
            try markGameSidebarBucketsDirty(rootIDs: touchedRootIDs)
        }
        if !touchedRootIDs.isEmpty { try refreshDirtyGameSidebarBuckets() }
        preferEmbeddedConsoleTags = preferEmbeddedMetadata
    }

    func refreshDirtyGameSidebarBuckets() throws {
        let sql = """
        SELECT id
        FROM library_roots
        WHERE game_sidebar_buckets_dirty = 1
          AND is_enabled = 1
        ORDER BY id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }

        var rootIDs: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rootIDs.append(sqlite3_column_int64(statement, 0))
        }
        try rebuildGameSidebarBuckets(rootIDs: rootIDs)
    }

    func rebuildGameSidebarBucketsIfDirty(rootID: Int64) throws {
        let sql = "SELECT game_sidebar_buckets_dirty FROM library_roots WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        sqliteBind(.int(rootID), to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return }
        guard sqlite3_column_int(statement, 0) != 0 else { return }
        try rebuildGameSidebarBuckets(rootIDs: [rootID])
    }

    func markGameSidebarBucketsDirty(rootIDs: Set<Int64>) throws {
        guard !rootIDs.isEmpty else { return }
        for rootID in rootIDs {
            try execute(
                "UPDATE library_roots SET game_sidebar_buckets_dirty = 1 WHERE id = ?;",
                bindings: [.int(rootID)]
            )
        }
    }

    private func rebuildGameSidebarBuckets(rootIDs: [Int64]) throws {
        guard !rootIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: rootIDs.count).joined(separator: ", ")
        let bindings = rootIDs.map(SQLiteValue.int)
        try withSavepoint {
            try execute(
                "DELETE FROM game_sidebar_buckets WHERE root_id IN (\(placeholders));",
                bindings: bindings
            )
            try execute(
                """
                INSERT INTO game_sidebar_buckets (root_id, browser_game, browser_system, track_count)
                SELECT t.root_id, t.browser_game, t.browser_system, COUNT(*)
                FROM tracks t
                WHERE t.root_id IN (\(placeholders))
                  AND NOT EXISTS (
                      SELECT 1 FROM dead_sources d
                      WHERE d.root_id = t.root_id AND d.path = t.path
                  )
                GROUP BY t.root_id, t.browser_game, t.browser_system;
                """,
                bindings: bindings
            )
            try execute(
                "UPDATE library_roots SET game_sidebar_buckets_dirty = 0 WHERE id IN (\(placeholders));",
                bindings: bindings
            )
        }
    }
}
