import SQLite3

extension LibraryDatabase {
    func migrateSchemaIfNeeded() throws {
        let version = try userVersion()
        guard version != Self.schemaVersion else { return }

        // Files-sidebar archive activation addresses a source by exactly its
        // library root and path. The former tree index inserted `folder_path`
        // between those fields, which forced SQLite to walk a whole large
        // root before it could find one selected archive. Preserve the
        // inspected library while adding the direct source lookup index.
        if version == 16 {
            try execute("CREATE INDEX IF NOT EXISTS tracks_source_lookup_index ON tracks(root_id, path);")
            try setUserVersion(Self.schemaVersion)
            return
        }

        try execute("PRAGMA foreign_keys = OFF;")
        try execute("BEGIN TRANSACTION;")
        do {
            try dropAllApplicationTables()
            try createLibraryRootTable()
            try createTrackTables()
            try createScanTables()
            try createDeadSourceTable()
            try createGameSidebarBucketTable()
            try createFileSidebarBucketTable()
            try setUserVersion(Self.schemaVersion)
            try execute("COMMIT;")
            try execute("PRAGMA foreign_keys = ON;")
        } catch {
            try? execute("ROLLBACK;")
            try? execute("PRAGMA foreign_keys = ON;")
            throw error
        }
    }

    private func dropAllApplicationTables() throws {
        var statement: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }

        var tableNames: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            tableNames.append(sqliteString(statement, index: 0))
        }
        for tableName in tableNames {
            let identifier = tableName.replacingOccurrences(of: "\"", with: "\"\"")
            try execute("DROP TABLE \"\(identifier)\";")
        }
    }

    private func createLibraryRootTable() throws {
        try execute("""
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
            is_attached INTEGER NOT NULL DEFAULT 1,
            game_sidebar_buckets_dirty INTEGER NOT NULL DEFAULT 1,
            file_sidebar_buckets_dirty INTEGER NOT NULL DEFAULT 1
        );
        """)
    }

    private func createDeadSourceTable() throws {
        try execute("""
        CREATE TABLE dead_sources (
            root_id INTEGER NOT NULL,
            path TEXT NOT NULL,
            marked_at REAL NOT NULL,
            PRIMARY KEY(root_id, path),
            FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE
        );
        """)
        try execute("CREATE INDEX dead_sources_path_index ON dead_sources(path);")
    }

    private func createGameSidebarBucketTable() throws {
        try execute("""
        CREATE TABLE game_sidebar_buckets (
            root_id INTEGER NOT NULL,
            browser_game TEXT NOT NULL,
            browser_system TEXT NOT NULL,
            track_count INTEGER NOT NULL,
            PRIMARY KEY(root_id, browser_game, browser_system),
            FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE
        );
        """)
    }

    private func createFileSidebarBucketTable() throws {
        try execute("""
        CREATE TABLE file_sidebar_buckets (
            root_id INTEGER NOT NULL,
            folder_path TEXT NOT NULL,
            path TEXT NOT NULL,
            is_archive INTEGER NOT NULL,
            track_count INTEGER NOT NULL,
            PRIMARY KEY(root_id, path),
            FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE
        );
        """)
        try execute("CREATE INDEX file_sidebar_buckets_tree_index ON file_sidebar_buckets(root_id, folder_path, path);")
    }

    /// Repairs rows written before archive refresh replaced a source's entire
    /// member set. A member row must carry the same outer-archive fingerprint
    /// as its parent inventory record; an older fingerprint means a repack
    /// already replaced that archive and the row is stale.
    func pruneStaleArchiveMembers() throws {
        try execute("BEGIN TRANSACTION;")
        do {
            try execute("""
            DELETE FROM tracks
            WHERE archive_entry IS NOT NULL
              AND EXISTS (
                  SELECT 1
                  FROM scan_items parent
                  WHERE parent.root_id = tracks.root_id
                    AND parent.path = tracks.path
                    AND parent.archive_entry = ''
                    AND (
                        parent.file_size <> tracks.file_size
                        OR parent.modified_at <> tracks.modified_at
                    )
              );
            """)
            try execute("""
            DELETE FROM scan_items
            WHERE archive_entry <> ''
              AND EXISTS (
                  SELECT 1
                  FROM scan_items parent
                  WHERE parent.root_id = scan_items.root_id
                    AND parent.path = scan_items.path
                    AND parent.archive_entry = ''
                    AND (
                        parent.file_size <> scan_items.file_size
                        OR parent.modified_at <> scan_items.modified_at
                    )
              );
            """)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
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
        try execute("CREATE INDEX tracks_browser_bucket_index ON tracks(browser_game, browser_system, root_id);")
        try execute("CREATE INDEX tracks_file_tree_index ON tracks(root_id, folder_path, path);")
        try execute("CREATE INDEX tracks_source_lookup_index ON tracks(root_id, path);")
        try execute("CREATE INDEX tracks_game_sidebar_index ON tracks(browser_game, browser_system, root_id, path);")
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
