import Foundation
import SQLite3

extension LibraryDatabase {
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
