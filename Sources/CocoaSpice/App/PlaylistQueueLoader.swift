import Foundation
import OSLog

struct LoadedPlaylistData: Sendable {
    let tracks: [TrackItem]
    let metadata: [String: TrackMetadata]
    let widthHints: PlaylistColumnWidthHints
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
    /// Sidebar selection is interactive database work. Keep it off Swift's
    /// cooperative executor so decoder, archive, and scan jobs cannot delay a
    /// small indexed playlist read.
    private static let databaseReadQueue = DispatchQueue(
        label: "com.local.cocoaspice.playlist-database-read",
        qos: .userInitiated
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
        gameItems: [DatabaseGameItem]
    ) async -> LoadedPlaylistData {
        guard let databaseURL else { return emptyLoadedPlaylistData() }
        return await withCheckedContinuation { continuation in
            databaseReadQueue.async {
            Self.playlistLoadLogger.info("sidebar database worker began")
            let queryStartedAt = ContinuousClock.now
            let loaded = (try? LibraryDatabase.tracksAndMetadataForGames(
                databaseURL: databaseURL,
                gameItems: gameItems
            )).map(loadedPlaylistData(from:)) ?? emptyLoadedPlaylistData()
            let queryElapsed = queryStartedAt.duration(to: .now)
            Self.playlistLoadLogger.info(
                "sidebar SQLite query finished: \(loaded.tracks.count) tracks in \(String(describing: queryElapsed), privacy: .public)"
            )
                continuation.resume(returning: loaded)
            }
        }
    }

    static func loadLibraryTracks(
        databaseURL: URL?,
        request: LibraryPlaylistLoadRequest
    ) async -> LoadedPlaylistData {
        switch request {
        case .games(let gameItems):
            return await loadLibraryTracksForGames(databaseURL: databaseURL, gameItems: gameItems)
        case .files(let fileItems):
            return await loadLibraryTracksForFiles(databaseURL: databaseURL, fileItems: fileItems)
        case .fileSidebar(let fileItems, let folders):
            return await loadLibraryTracksForFileSidebarSelection(
                databaseURL: databaseURL,
                fileItems: fileItems,
                folders: folders
            )
        }
    }

    static func loadLibraryTracksForFiles(
        databaseURL: URL?,
        fileItems: [DatabaseFileItem]
    ) async -> LoadedPlaylistData {
        await Task.detached(priority: .userInitiated) {
            guard let databaseURL else { return emptyLoadedPlaylistData() }
            let loaded = (try? LibraryDatabase.tracksAndMetadataForFiles(
                databaseURL: databaseURL,
                fileItems: fileItems
            )).map(loadedPlaylistData(from:)) ?? emptyLoadedPlaylistData()
            return loaded
        }.value
    }

    static func loadLibraryTracksForFolder(
        databaseURL: URL?,
        rootPath: String,
        folderPath: String
    ) async -> LoadedPlaylistData {
        await Task.detached(priority: .userInitiated) {
            guard let databaseURL else { return emptyLoadedPlaylistData() }
            return (try? LibraryDatabase.tracksAndMetadataForFolder(
                databaseURL: databaseURL,
                rootPath: rootPath,
                folderPath: folderPath
            )).map(loadedPlaylistData(from:)) ?? emptyLoadedPlaylistData()
        }.value
    }

    static func loadLibraryTracksForFileSidebarSelection(
        databaseURL: URL?,
        fileItems: [DatabaseFileItem],
        folders: [DatabaseFileSidebarFolder]
    ) async -> LoadedPlaylistData {
        await Task.detached(priority: .userInitiated) {
            guard let databaseURL else { return emptyLoadedPlaylistData() }

            var tracks: [TrackItem] = []
            var metadata: [String: TrackMetadata] = [:]
            var seenTrackIDs = Set<String>()

            func merge(_ loaded: (tracks: [TrackItem], metadata: [String: TrackMetadata], widthHints: PlaylistColumnWidthHints)) {
                for track in loaded.tracks where seenTrackIDs.insert(track.id).inserted {
                    tracks.append(track)
                    if let itemMetadata = loaded.metadata[track.id] {
                        metadata[track.id] = itemMetadata
                    }
                }
            }

            if !fileItems.isEmpty,
               let loaded = try? LibraryDatabase.tracksAndMetadataForFiles(
                   databaseURL: databaseURL,
                   fileItems: fileItems
               ) {
                merge(loaded)
            }

            for folder in folders.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
                guard let loaded = try? LibraryDatabase.tracksAndMetadataForFolder(
                    databaseURL: databaseURL,
                    rootPath: folder.rootPath,
                    folderPath: folder.path
                ) else {
                    continue
                }
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
    ) async -> LoadedPlaylistData {
        await Task.detached(priority: .userInitiated) {
            guard let databaseURL else { return emptyLoadedPlaylistData() }
            return (try? LibraryDatabase.tracksAndMetadataForPaths(
                databaseURL: databaseURL,
                paths: paths
            )).map(loadedPlaylistData(from:)) ?? emptyLoadedPlaylistData()
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
        var importedMetadata: [String: TrackMetadata] = [:]
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
                            into: &importedTracks,
                            metadata: &importedMetadata
                        )
                        continue
                    }
                    await appendFile(
                        fileURL,
                        into: &importedTracks,
                        metadata: &importedMetadata
                    )
                }
                continue
            }

            if ZipArchiveSupport.canHandle(url) {
                await appendArchive(
                    url,
                    into: &importedTracks,
                    metadata: &importedMetadata
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
                merge(
                    inspectedTracks: tracks.map { InspectedTrack(track: $0, metadata: emptyMetadata()) },
                    into: &importedTracks,
                    metadata: &importedMetadata
                )
                continue
            }

            guard PlaybackFormatRegistry.admits(fileURL: url) else {
                continue
            }

            await appendFile(
                url,
                into: &importedTracks,
                metadata: &importedMetadata
            )
        }

        guard !importedTracks.isEmpty else {
            return emptyLoadedPlaylistData()
        }

        return LoadedPlaylistData(
            tracks: importedTracks,
            metadata: importedMetadata,
            widthHints: PlaylistPresentation.buildColumnWidthHints(
                tracks: importedTracks,
                metadata: importedMetadata
            )
        )
    }

    private static func loadedPlaylistData(
        from tuple: (
            tracks: [TrackItem],
            metadata: [String: TrackMetadata],
            widthHints: PlaylistColumnWidthHints
        )
    ) -> LoadedPlaylistData {
        LoadedPlaylistData(
            tracks: tuple.tracks,
            metadata: tuple.metadata,
            widthHints: tuple.widthHints
        )
    }

    private static func directoryPlayableFileURLs(in folderURL: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter {
                ZipArchiveSupport.canHandle($0)
                    || PlaybackFormatRegistry.admits(fileURL: $0)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func inspectPlayableTracks(forFileURL fileURL: URL) async -> [InspectedTrack] {
        if let inspectedTracks = try? await PlaybackInspection.inspectPlayableTracks(fileURL: fileURL),
           !inspectedTracks.isEmpty {
            return inspectedTracks
        }

        return [
            InspectedTrack(track: TrackItem(url: fileURL), metadata: emptyMetadata())
        ]
    }

    private static func appendFile(
        _ fileURL: URL,
        into tracks: inout [TrackItem],
        metadata: inout [String: TrackMetadata]
    ) async {
        guard PlaybackFormatRegistry.requiresTrackEnumeration(
            forPathExtension: fileURL.pathExtension
        ) else {
            tracks.append(TrackItem(url: fileURL))
            return
        }

        merge(
            inspectedTracks: await inspectPlayableTracks(forFileURL: fileURL),
            into: &tracks,
            metadata: &metadata
        )
    }

    private static func appendArchiveEntry(
        _ entry: ZipArchiveSupport.ArchiveEntry,
        into tracks: inout [TrackItem],
        metadata: inout [String: TrackMetadata]
    ) async {
        let extensionName = URL(fileURLWithPath: entry.entryPath).pathExtension
        guard PlaybackFormatRegistry.requiresTrackEnumeration(
            forPathExtension: extensionName
        ) else {
            tracks.append(TrackItem(archiveURL: entry.archiveURL, entryPath: entry.entryPath))
            return
        }

        merge(
            inspectedTracks: await inspectPlayableTracks(forArchiveEntry: entry),
            into: &tracks,
            metadata: &metadata
        )
    }

    private static func appendArchive(
        _ archiveURL: URL,
        into tracks: inout [TrackItem],
        metadata: inout [String: TrackMetadata]
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
            await appendArchiveEntry(entry, into: &tracks, metadata: &metadata)
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
            guard let playlistURL = try? ZipArchiveSupport.materializeEntry(
                archiveURL: archiveURL,
                entryPath: playlistEntry.entryPath
            ),
            let contents = try? String(contentsOf: playlistURL, encoding: .utf8) else {
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

    private static func inspectPlayableTracks(
        forArchiveEntry entry: ZipArchiveSupport.ArchiveEntry
    ) async -> [InspectedTrack] {
        guard let materializedURL = try? ZipArchiveSupport.materializeEntry(
            archiveURL: entry.archiveURL,
            entryPath: entry.entryPath
        ) else {
            return []
        }

        if let inspectedTracks = try? await PlaybackInspection.inspectPlayableTracks(fileURL: materializedURL),
           !inspectedTracks.isEmpty {
            return inspectedTracks.map { inspectedTrack in
                InspectedTrack(
                    track: TrackItem(
                        archiveURL: entry.archiveURL,
                        entryPath: entry.entryPath,
                        trackIndex: inspectedTrack.track.trackIndex,
                        trackCount: inspectedTrack.track.trackCount
                    ),
                    metadata: inspectedTrack.metadata
                )
            }
        }

        return [
            InspectedTrack(
                track: TrackItem(archiveURL: entry.archiveURL, entryPath: entry.entryPath),
                metadata: emptyMetadata()
            )
        ]
    }

    private static func merge(
        inspectedTracks: [InspectedTrack],
        into tracks: inout [TrackItem],
        metadata: inout [String: TrackMetadata]
    ) {
        for inspectedTrack in inspectedTracks {
            tracks.append(inspectedTrack.track)
            if inspectedTrack.metadata != emptyMetadata() {
                metadata[inspectedTrack.track.id] = inspectedTrack.metadata
            }
        }
    }

    private static func emptyMetadata() -> TrackMetadata {
        TrackMetadata(
            game: "",
            song: "",
            system: "",
            author: "",
            comment: "",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: 0,
            fadeLengthMs: 0
        )
    }
}
