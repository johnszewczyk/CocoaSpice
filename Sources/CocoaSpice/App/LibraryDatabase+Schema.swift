import SQLite3

extension LibraryDatabase {
    func migrateSchemaIfNeeded() throws {
        let version = try userVersion()
        if version < 4 {
            try execute("DROP TABLE IF EXISTS track_metadata;")
            try execute("DROP TABLE IF EXISTS tracks;")
            try createTrackTables()
        }
        if version < 5 {
            try createScanTables()
        }
        if version >= 4, version < 6 {
            try migrateTracksToRootScopedIdentity()
        }
        if version < 7 {
            try execute("ALTER TABLE library_roots ADD COLUMN is_attached INTEGER NOT NULL DEFAULT 1;")
        }
        if version >= 5, version < 8 {
            try execute("ALTER TABLE scan_items ADD COLUMN content_signature TEXT;")
        }
        if version >= 6, version < 9 {
            try execute("ALTER TABLE tracks ADD COLUMN browser_game TEXT NOT NULL DEFAULT '';")
            try execute("ALTER TABLE tracks ADD COLUMN browser_system TEXT NOT NULL DEFAULT '';")
        }
        if version >= 4, version < 9 {
            try execute("""
            UPDATE tracks
            SET
                browser_game = COALESCE(
                    NULLIF(TRIM((SELECT game FROM track_metadata WHERE track_id = tracks.id)), ''),
                    COALESCE(archive_path, folder_path)
                ),
                browser_system = COALESCE(
                    TRIM((SELECT system FROM track_metadata WHERE track_id = tracks.id)),
                    ''
                );
            """)
        }
        if version < 9 {
            try execute("CREATE INDEX IF NOT EXISTS tracks_browser_bucket_index ON tracks(browser_game, browser_system, root_id);")
        }
        if version < 10 {
            try execute("CREATE INDEX IF NOT EXISTS tracks_file_tree_index ON tracks(root_id, folder_path, path);")
        }
        if version < 11 {
            // Legacy filename-only placeholders are not complete library rows.
            // Remove their inventory too, so the next incremental scan replaces
            // them with normal archive/member metadata.
            try execute("""
            DELETE FROM scan_items
            WHERE EXISTS (
                SELECT 1
                FROM tracks t
                INNER JOIN track_metadata m ON m.track_id = t.id
                WHERE t.root_id = scan_items.root_id
                  AND t.path = scan_items.path
                  AND m.comment = '__cocoaspice_fast_scan__'
            );
            """)
            try execute("""
            DELETE FROM tracks
            WHERE id IN (
                SELECT track_id
                FROM track_metadata
                WHERE comment = '__cocoaspice_fast_scan__'
            );
            """)
        }
        if version < 12 {
            try execute("""
            CREATE TABLE IF NOT EXISTS dead_sources (
                root_id INTEGER NOT NULL,
                path TEXT NOT NULL,
                marked_at REAL NOT NULL,
                PRIMARY KEY(root_id, path),
                FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE
            );
            """)
            try execute("CREATE INDEX IF NOT EXISTS dead_sources_path_index ON dead_sources(path);")
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
            browser_game TEXT NOT NULL DEFAULT '',
            browser_system TEXT NOT NULL DEFAULT '',
            track_index INTEGER NOT NULL DEFAULT 0,
            track_count INTEGER NOT NULL DEFAULT 1,
            file_size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            discovered_at REAL NOT NULL,
            archive_path TEXT,
            archive_entry TEXT,
            UNIQUE(root_id, path, archive_entry, track_index),
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
            content_signature TEXT,
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

    private func migrateTracksToRootScopedIdentity() throws {
        try execute("ALTER TABLE track_metadata RENAME TO track_metadata_legacy;")
        try execute("ALTER TABLE tracks RENAME TO tracks_legacy;")
        try createTrackTables()
        try execute("""
        INSERT INTO tracks (id, root_id, folder_path, path, filename, extension, track_index, track_count, file_size, modified_at, discovered_at, archive_path, archive_entry)
        SELECT id, root_id, folder_path, path, filename, extension, track_index, track_count, file_size, modified_at, discovered_at, archive_path, archive_entry
        FROM tracks_legacy;
        """)
        try execute("""
        INSERT INTO track_metadata (track_id, title, game, author, system, comment, intro_length_ms, loop_length_ms, play_length_ms, fade_length_ms, metadata_scanned_at)
        SELECT track_id, title, game, author, system, comment, intro_length_ms, loop_length_ms, play_length_ms, fade_length_ms, metadata_scanned_at
        FROM track_metadata_legacy;
        """)
        try execute("DROP TABLE track_metadata_legacy;")
        try execute("DROP TABLE tracks_legacy;")
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
}
