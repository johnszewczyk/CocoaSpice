import Foundation
import CatalogReader
import CatalogPlaylistCore
import SQLite3

extension LibraryDatabase {
    func searchSidebarItems(query: String, limit: Int = 250) throws -> [SidebarSearchItem] {
        try Self.searchSidebarItems(databaseURL: databaseURL, query: query, limit: limit)
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

    static func tracksAndMetadataForGames(
        databaseURL: URL,
        gameItems: [DatabaseGameItem],
        preferFoldersOverMetadata: Bool = true
    ) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        let normalizedItems = Array(NSOrderedSet(array: gameItems)) as? [DatabaseGameItem] ?? []
        guard !normalizedItems.isEmpty else {
            return ([], [:], PlaylistColumnWidthHints(indexText: "1", fileText: "", titleText: "", gameText: "", authorText: "", systemText: "", lengthText: "—"))
        }

        let selections = normalizedItems.map {
            CatalogPlaylistGameSelection(rootID: $0.rootID, game: $0.name, system: $0.systemName)
        }
        let catalogTracks = try CatalogPlaylistReader.tracksForGames(
            databaseURL: databaseURL,
            selections: selections,
            preferFoldersOverMetadata: preferFoldersOverMetadata
        )

        var tracks: [TrackItem] = []
        var metadata: [String: TrackMetadata] = [:]
        var widestFileText = ""
        var widestTitleText = ""
        var widestGameText = ""
        var widestAuthorText = ""
        var widestSystemText = ""
        var widestLengthText = "—"
        for catalogTrack in catalogTracks {
            let track = track(from: catalogTrack)
            let title = catalogTrack.title
            let game = catalogTrack.game
            let author = catalogTrack.author
            let system = catalogTrack.system
            let comment = catalogTrack.comment
            let introLengthMs = catalogTrack.introLengthMilliseconds
            let loopLengthMs = catalogTrack.loopLengthMilliseconds
            let playLengthMs = catalogTrack.lengthMilliseconds
            let fadeLengthMs = catalogTrack.fadeLengthMilliseconds
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

    static func tracksAndMetadataForFiles(databaseURL: URL, fileItems: [DatabaseFileItem]) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        let normalizedItems = Array(NSOrderedSet(array: fileItems)) as? [DatabaseFileItem] ?? []
        guard !normalizedItems.isEmpty else {
            return ([], [:], PlaylistColumnWidthHints(indexText: "1", fileText: "", titleText: "", gameText: "", authorText: "", systemText: "", lengthText: "—"))
        }

        let catalog = try ReadOnlyCatalog(databaseURL: databaseURL)
        let selections = normalizedItems.map {
            CatalogSourceSelection(rootID: $0.rootID, path: $0.path)
        }
        return playlistProjection(from: try catalog.tracks(sourceSelections: selections))
    }

    static func tracksAndMetadataForFolder(databaseURL: URL, rootPath: String, folderPath: String) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        let catalog = try ReadOnlyCatalog(databaseURL: databaseURL)
        return playlistProjection(from: try catalog.tracks(rootPath: rootPath, folderPath: folderPath))
    }

    static func tracksAndMetadataForPaths(databaseURL: URL, paths: [String]) throws -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        let normalizedPaths = Array(NSOrderedSet(array: paths.map {
            URL(fileURLWithPath: $0, isDirectory: false).standardizedFileURL.path
        })) as? [String] ?? []
        guard !normalizedPaths.isEmpty else {
            return ([], [:], PlaylistColumnWidthHints(indexText: "1", fileText: "", titleText: "", gameText: "", authorText: "", systemText: "", lengthText: "—"))
        }

        let catalog = try ReadOnlyCatalog(databaseURL: databaseURL)
        return playlistProjection(from: try catalog.tracks(paths: normalizedPaths))
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

    /// Adapts the shared catalog projection into CocoaSpice's queue and
    /// presentation models. The database reader owns selection and metadata
    /// retrieval; CocoaSpice retains only frontend-specific row sizing.
    private static func playlistProjection(
        from catalogTracks: [CatalogTrack]
    ) -> (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints) {
        var tracks: [TrackItem] = []
        var metadata: [String: TrackMetadata] = [:]
        var widestFileText = ""
        var widestTitleText = ""
        var widestGameText = ""
        var widestAuthorText = ""
        var widestSystemText = ""
        var widestLengthText = "—"

        for catalogTrack in catalogTracks {
            let track = track(from: catalogTrack)
            tracks.append(track)
            metadata[track.id] = TrackMetadata(
                game: catalogTrack.game,
                song: catalogTrack.title,
                system: catalogTrack.system,
                author: catalogTrack.author,
                comment: catalogTrack.comment,
                introLengthMs: catalogTrack.introLengthMilliseconds,
                loopLengthMs: catalogTrack.loopLengthMilliseconds,
                playLengthMs: catalogTrack.lengthMilliseconds,
                fadeLengthMs: catalogTrack.fadeLengthMilliseconds
            )

            widestFileText = widerText(widestFileText, track.filename)
            widestTitleText = widerText(widestTitleText, catalogTrack.title.isEmpty ? track.displayName : catalogTrack.title)
            widestGameText = widerText(widestGameText, catalogTrack.game.isEmpty ? track.url.deletingLastPathComponent().lastPathComponent : catalogTrack.game)
            widestAuthorText = widerText(widestAuthorText, catalogTrack.author.isEmpty ? "—" : catalogTrack.author)
            widestSystemText = widerText(widestSystemText, catalogTrack.system.isEmpty ? "SNES" : catalogTrack.system)
            widestLengthText = widerText(widestLengthText, formatLengthText(playLengthMs: catalogTrack.lengthMilliseconds))
        }

        return (
            tracks,
            metadata,
            PlaylistColumnWidthHints(
                indexText: String(max(1, tracks.count)),
                fileText: widestFileText,
                titleText: widestTitleText,
                gameText: widestGameText,
                authorText: widestAuthorText,
                systemText: widestSystemText,
                lengthText: widestLengthText
            )
        )
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

    private static func track(from catalogTrack: CatalogPlaylistTrack) -> TrackItem {
        if let archivePath = catalogTrack.archivePath,
           let archiveEntry = catalogTrack.archiveEntry,
           !archivePath.isEmpty,
           !archiveEntry.isEmpty {
            return TrackItem(
                archiveURL: URL(fileURLWithPath: archivePath, isDirectory: false),
                entryPath: archiveEntry,
                trackIndex: catalogTrack.trackIndex,
                trackCount: catalogTrack.trackCount
            )
        }
        return TrackItem(
            url: URL(fileURLWithPath: catalogTrack.sourcePath, isDirectory: false),
            trackIndex: catalogTrack.trackIndex,
            trackCount: catalogTrack.trackCount
        )
    }

    private static func track(from catalogTrack: CatalogTrack) -> TrackItem {
        if let archivePath = catalogTrack.archivePath,
           let archiveEntry = catalogTrack.archiveEntry,
           !archivePath.isEmpty,
           !archiveEntry.isEmpty {
            return TrackItem(
                archiveURL: URL(fileURLWithPath: archivePath, isDirectory: false),
                entryPath: archiveEntry,
                trackIndex: catalogTrack.trackIndex,
                trackCount: catalogTrack.trackCount
            )
        }
        return TrackItem(
            url: URL(fileURLWithPath: catalogTrack.sourcePath, isDirectory: false),
            trackIndex: catalogTrack.trackIndex,
            trackCount: catalogTrack.trackCount
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
