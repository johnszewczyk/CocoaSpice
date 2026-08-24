import Foundation
import LocalFileBrowserCore
import OSLog

struct LoadedPlaylistData: Sendable {
    let tracks: [TrackItem]
    let metadata: [String: TrackMetadata]
    let widthHints: PlaylistColumnWidthHints
}

enum PlaylistQueueLoaderError: LocalizedError, Sendable {
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            "The library database is unavailable."
        }
    }
}

/// A database-backed sidebar selection awaiting playlist materialization.
enum LibraryPlaylistLoadRequest: Sendable {
    case games([DatabaseGameItem])
    case files([DatabaseFileItem])
    case fileSidebar(fileItems: [DatabaseFileItem], folders: [DatabaseFileSidebarFolder])
}

enum PlaylistQueueLoader {
    private static let playlistLoadLogger = Logger(
        subsystem: "com.local.cocoaspice",
        category: "playlist-load"
    )
    /// Sidebar selection is interactive database work. Each request opens a
    /// read-only SQLite connection, so requests must not queue behind stale
    /// clicks; PlayerViewModel's generation guard discards their old results.
    private static let databaseReadQueue = DispatchQueue(
        label: "com.local.cocoaspice.playlist-database-read",
        qos: .userInitiated,
        attributes: .concurrent
    )
    static func loadTracks(in folderURL: URL) async -> [TrackItem] {
        let loaded = await loadDroppedTracks(from: [folderURL])
        return loaded.tracks
    }

    static func canImportDroppedURL(_ url: URL) -> Bool {
        let url = url.standardizedFileURL
        if ZipArchiveSupport.canHandle(url) {
            return true
        }
        if url.pathExtension.lowercased() == "m3u" {
            return true
        }
        if PlaybackFormatRegistry.admits(fileURL: url) {
            return true
        }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    static func loadDroppedTracks(from urls: [URL]) async -> LoadedPlaylistData {
        await Task.detached(priority: .userInitiated) {
            await loadDroppedTracksDetached(from: urls)
        }.value
    }

    static func loadLibraryTracksForGames(
        databaseURL: URL?,
        gameItems: [DatabaseGameItem],
        preferFoldersOverMetadata: Bool = true
    ) async throws -> LoadedPlaylistData {
        guard let databaseURL else { throw PlaylistQueueLoaderError.databaseUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            databaseReadQueue.async {
                Self.playlistLoadLogger.info("sidebar database worker began")
                let queryStartedAt = ContinuousClock.now
                do {
                    // CatalogReader owns the shared compact root/game/system
                    // projection. Keep queue construction on that proven
                    // read-only path and adapt its rows to CocoaSpice types.
                    let result = try LibraryDatabase.tracksAndMetadataForGames(
                        databaseURL: databaseURL,
                        gameItems: gameItems,
                        preferFoldersOverMetadata: preferFoldersOverMetadata
                    )
                    let loaded = LoadedPlaylistData(
                        tracks: result.tracks,
                        metadata: result.metadata,
                        widthHints: result.widthHints
                    )
                    let queryElapsed = queryStartedAt.duration(to: .now)
                    Self.playlistLoadLogger.info(
                        "sidebar SQLite query finished: \(loaded.tracks.count) tracks in \(String(describing: queryElapsed), privacy: .public)"
                    )
                    continuation.resume(returning: loaded)
                } catch {
                    Self.playlistLoadLogger.error("sidebar SQLite query failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func loadLibraryTracks(
        databaseURL: URL?,
        request: LibraryPlaylistLoadRequest,
        preferFoldersOverMetadata: Bool = true
    ) async throws -> LoadedPlaylistData {
        switch request {
        case .games(let gameItems):
            return try await loadLibraryTracksForGames(
                databaseURL: databaseURL,
                gameItems: gameItems,
                preferFoldersOverMetadata: preferFoldersOverMetadata
            )
        case .files(let fileItems):
            return try await loadLibraryTracksForFiles(databaseURL: databaseURL, fileItems: fileItems)
        case .fileSidebar(let fileItems, let folders):
            return try await loadLibraryTracksForFileSidebarSelection(
                databaseURL: databaseURL,
                fileItems: fileItems,
                folders: folders
            )
        }
    }

    static func loadLibraryTracksForFiles(
        databaseURL: URL?,
        fileItems: [DatabaseFileItem]
    ) async throws -> LoadedPlaylistData {
        try await Task.detached(priority: .userInitiated) {
            guard let databaseURL else { throw PlaylistQueueLoaderError.databaseUnavailable }
            let result = try LibraryDatabase.tracksAndMetadataForFiles(
                databaseURL: databaseURL,
                fileItems: fileItems
            )
            return LoadedPlaylistData(tracks: result.tracks, metadata: result.metadata, widthHints: result.widthHints)
        }.value
    }

    static func loadLibraryTracksForFolder(
        databaseURL: URL?,
        rootPath: String,
        folderPath: String
    ) async throws -> LoadedPlaylistData {
        try await Task.detached(priority: .userInitiated) {
            guard let databaseURL else { throw PlaylistQueueLoaderError.databaseUnavailable }
            let result = try LibraryDatabase.tracksAndMetadataForFolder(
                databaseURL: databaseURL,
                rootPath: rootPath,
                folderPath: folderPath
            )
            return LoadedPlaylistData(tracks: result.tracks, metadata: result.metadata, widthHints: result.widthHints)
        }.value
    }

    static func loadLibraryTracksForFileSidebarSelection(
        databaseURL: URL?,
        fileItems: [DatabaseFileItem],
        folders: [DatabaseFileSidebarFolder]
    ) async throws -> LoadedPlaylistData {
        try await Task.detached(priority: .userInitiated) {
            guard let databaseURL else { throw PlaylistQueueLoaderError.databaseUnavailable }

            var tracks: [TrackItem] = []
            var metadata: [String: TrackMetadata] = [:]
            var seenTrackIDs = Set<String>()

            func merge(_ loaded: LoadedPlaylistData) {
                for track in loaded.tracks where seenTrackIDs.insert(track.id).inserted {
                    tracks.append(track)
                    if let itemMetadata = loaded.metadata[track.id] {
                        metadata[track.id] = itemMetadata
                    }
                }
            }

            if !fileItems.isEmpty {
                let result = try LibraryDatabase.tracksAndMetadataForFiles(databaseURL: databaseURL, fileItems: fileItems)
                merge(LoadedPlaylistData(tracks: result.tracks, metadata: result.metadata, widthHints: result.widthHints))
            }

            for folder in folders.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
                let result = try LibraryDatabase.tracksAndMetadataForFolder(
                    databaseURL: databaseURL,
                    rootPath: folder.rootPath,
                    folderPath: folder.path
                )
                let loaded = LoadedPlaylistData(tracks: result.tracks, metadata: result.metadata, widthHints: result.widthHints)
                merge(loaded)
            }

            guard !tracks.isEmpty else { return emptyLoadedPlaylistData() }
            return LoadedPlaylistData(
                tracks: tracks,
                metadata: metadata,
                widthHints: PlaylistPresentation.buildColumnWidthHints(tracks: tracks, metadata: metadata)
            )
        }.value
    }

    static func loadLibraryTracksForPaths(
        databaseURL: URL?,
        paths: [String]
    ) async throws -> LoadedPlaylistData {
        try await Task.detached(priority: .userInitiated) {
            guard let databaseURL else { throw PlaylistQueueLoaderError.databaseUnavailable }
            let result = try LibraryDatabase.tracksAndMetadataForPaths(databaseURL: databaseURL, paths: paths)
            return LoadedPlaylistData(tracks: result.tracks, metadata: result.metadata, widthHints: result.widthHints)
        }.value
    }

    private static func emptyLoadedPlaylistData() -> LoadedPlaylistData {
        LoadedPlaylistData(
            tracks: [],
            metadata: [:],
            widthHints: PlaylistColumnWidthHints(
                indexText: "1",
                fileText: "",
                titleText: "",
                gameText: "",
                authorText: "",
                systemText: "",
                lengthText: "—"
            )
        )
    }

    private static func loadDroppedTracksDetached(from urls: [URL]) async -> LoadedPlaylistData {
        var importedTracks: [TrackItem] = []
        var seenPaths = Set<String>()
        let uniqueURLs = urls
            .map(\.standardizedFileURL)
            .filter { seenPaths.insert($0.path).inserted }

        for url in uniqueURLs {
            if Task.isCancelled {
                return emptyLoadedPlaylistData()
            }

            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let fileURLs = directoryPlayableFileURLs(in: url)
                for fileURL in fileURLs {
                    if ZipArchiveSupport.canHandle(fileURL) {
                        await appendArchive(
                            fileURL,
                            into: &importedTracks
                        )
                        continue
                    }
                    await appendFile(
                        fileURL,
                        into: &importedTracks
                    )
                }
                continue
            }

            if ZipArchiveSupport.canHandle(url) {
                await appendArchive(
                    url,
                    into: &importedTracks
                )
                continue
            }

            if url.pathExtension.lowercased() == "m3u" {
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    continue
                }
                let tracks = PlaylistM3UCodec.decode(
                    contents,
                    baseDirectory: url.deletingLastPathComponent(),
                    supportedExtensions: PlaybackFormatRegistry.supportedExtensions
                )
                importedTracks.append(contentsOf: tracks)
                continue
            }

            guard PlaybackFormatRegistry.admits(fileURL: url) else {
                continue
            }

            await appendFile(
                url,
                into: &importedTracks
            )
        }

        guard !importedTracks.isEmpty else {
            return emptyLoadedPlaylistData()
        }

        return LoadedPlaylistData(
            tracks: importedTracks,
            metadata: [:],
            widthHints: PlaylistPresentation.buildColumnWidthHints(
                tracks: importedTracks,
                metadata: [:]
            )
        )
    }

    private static func directoryPlayableFileURLs(in folderURL: URL) -> [URL] {
        guard let session = try? LocalFileBrowserSession(
            rootURL: folderURL,
            isPlayableFile: { url in
                ZipArchiveSupport.canHandle(url) || PlaybackFormatRegistry.admits(fileURL: url)
            }
        ) else {
            return []
        }
        return (try? session.children(of: folderURL))?.filter { $0.kind == .file }
            .map { URL(fileURLWithPath: $0.path) }
            ?? []
    }

    private static func appendFile(
        _ fileURL: URL,
        into tracks: inout [TrackItem]
    ) async {
        tracks.append(TrackItem(url: fileURL))
    }

    private static func appendArchiveEntry(
        _ entry: ZipArchiveSupport.ArchiveEntry,
        into tracks: inout [TrackItem]
    ) async {
        tracks.append(TrackItem(archiveURL: entry.archiveURL, entryPath: entry.entryPath))
    }

    private static func appendArchive(
        _ archiveURL: URL,
        into tracks: inout [TrackItem]
    ) async {
        // An archive M3U deliberately owns its queue. If an archive provides
        // one, do not also append every sibling audio member afterwards.
        let playlistEntries = (try? ZipArchiveSupport.listPlaylistEntries(in: archiveURL)) ?? []
        let entries: [ZipArchiveSupport.ArchiveEntry]
        if playlistEntries.isEmpty {
            entries = (try? ZipArchiveSupport.listPlayableEntries(
                in: archiveURL,
                supportedExtensions: PlaybackFormatRegistry.supportedExtensions
            )) ?? []
        } else {
            entries = archivePlaylistReferencedEntries(
                archiveURL: archiveURL,
                playlistEntries: playlistEntries,
                supportedExtensions: PlaybackFormatRegistry.supportedExtensions
            )
        }

        for entry in entries {
            await appendArchiveEntry(entry, into: &tracks)
        }
    }

    private static func archivePlaylistReferencedEntries(
        archiveURL: URL,
        playlistEntries: [ZipArchiveSupport.ArchiveEntry],
        supportedExtensions: Set<String>
    ) -> [ZipArchiveSupport.ArchiveEntry] {
        guard let allEntries = try? ZipArchiveSupport.listPlayableEntries(
            in: archiveURL,
            supportedExtensions: supportedExtensions
        ) else {
            return []
        }
        let playablePaths = Set(allEntries.map(\.entryPath))
        var referencedEntries: [ZipArchiveSupport.ArchiveEntry] = []

        for playlistEntry in playlistEntries {
            guard let data = try? ZipArchiveSupport.contentsOfEntry(
                archiveURL: archiveURL,
                entryPath: playlistEntry.entryPath
            ),
            let contents = String(data: data, encoding: .utf8) else {
                continue
            }

            for rawLine in contents.split(whereSeparator: \.isNewline).map(String.init) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("/") else { continue }
                guard let entryPath = resolvedArchivePlaylistEntryPath(
                    line,
                    playlistEntryPath: playlistEntry.entryPath
                ) else { continue }
                guard playablePaths.contains(entryPath) else { continue }
                referencedEntries.append(
                    ZipArchiveSupport.ArchiveEntry(archiveURL: archiveURL, entryPath: entryPath)
                )
            }
        }
        return referencedEntries
    }

    /// Resolve within the archive namespace, not the host filesystem. A URL
    /// relative to a non-absolute path silently resolves from `/`, which would
    /// lose the M3U's directory and make `../audio/track.mp3` unfindable.
    private static func resolvedArchivePlaylistEntryPath(
        _ reference: String,
        playlistEntryPath: String
    ) -> String? {
        var components = playlistEntryPath.split(separator: "/").dropLast().map(String.init)
        for component in reference.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

}
