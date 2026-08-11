import Foundation
import SQLite3

extension LibraryDatabase {
    func loadRoots() throws -> [LibraryScanRoot] {
        let sql = """
        SELECT id, path, is_enabled, display_order, last_scan_started_at, last_scan_completed_at, last_scan_track_count, last_scan_error
        FROM library_roots
        WHERE is_attached = 1
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
            INSERT INTO library_roots (path, is_enabled, display_order, created_at, game_sidebar_buckets_dirty, file_sidebar_buckets_dirty)
            VALUES (?, 1, ?, ?, 0, 0)
            ON CONFLICT(path) DO UPDATE SET
                is_enabled = 1,
                is_attached = 1,
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
        if isEnabled {
            try rebuildGameSidebarBucketsIfDirty(rootID: id)
            try rebuildFileSidebarBucketsIfDirty(rootID: id)
        }
    }

    /// Persists a burst of checkbox changes as one short transaction. The
    /// caller owns the in-memory UI state, so this must not load roots or
    /// trigger sidebar work itself.
    func setRootEnabledStates(_ enabledStates: [Int64: Bool]) throws {
        guard !enabledStates.isEmpty else { return }
        try execute("BEGIN TRANSACTION;")
        do {
            for (id, isEnabled) in enabledStates {
                try execute(
                    "UPDATE library_roots SET is_enabled = ? WHERE id = ?;",
                    bindings: [.int(isEnabled ? 1 : 0), .int(id)]
                )
            }
            try execute("COMMIT;")
            try refreshDirtySidebarBuckets()
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func detachRoot(id: Int64) throws {
        try execute(
            "UPDATE library_roots SET is_attached = 0, is_enabled = 0 WHERE id = ?;",
            bindings: [.int(id)]
        )
    }

    func detachAttachedRoots() throws {
        try execute(
            "UPDATE library_roots SET is_attached = 0, is_enabled = 0 WHERE is_attached = 1;"
        )
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

    func markScanCompleted(rootID: Int64) throws {
        guard !isStagingFullScan(rootID: rootID) else { return }
        try rebuildGameSidebarBucketsIfDirty(rootID: rootID)
        try rebuildFileSidebarBucketsIfDirty(rootID: rootID)
        try execute(
            """
            UPDATE library_roots
            SET last_scan_completed_at = ?,
                last_scan_track_count = (
                    SELECT COALESCE(SUM(track_count), 0)
                    FROM game_sidebar_buckets
                    WHERE root_id = ?
                ),
                last_scan_error = NULL
            WHERE id = ?;
            """,
            bindings: [.double(Date().timeIntervalSince1970), .int(rootID), .int(rootID)]
        )
    }
}
