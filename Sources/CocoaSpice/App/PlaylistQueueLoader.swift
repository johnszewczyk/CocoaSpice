import Foundation

struct LoadedPlaylistData: Sendable {
    let tracks: [TrackItem]
    let metadata: [String: TrackMetadata]
    let widthHints: PlaylistColumnWidthHints
}

enum PlaylistQueueLoader {
    static func loadTracks(in folderURL: URL) async -> [TrackItem] {
        await Task.detached(priority: .utility) {
            SPCFileScanner.playlist(for: folderURL)
        }.value
    }

    static func canImportDroppedURL(_ url: URL) -> Bool {
        let url = url.standardizedFileURL
        if ZipArchiveSupport.canHandle(url) {
            return true
        }
        if url.pathExtension.lowercased() == "m3u" {
            return true
        }
        if SPCFileScanner.supportedExtensions.contains(url.pathExtension.lowercased()) {
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
        await Task.detached(priority: .userInitiated) {
            guard let databaseURL else { return emptyLoadedPlaylistData() }
            return (try? LibraryDatabase.tracksAndMetadataForGames(
                databaseURL: databaseURL,
                gameItems: gameItems
            )).map(loadedPlaylistData(from:)) ?? emptyLoadedPlaylistData()
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
                    let inspectedTracks = await inspectPlayableTracks(forFileURL: fileURL)
                    merge(
                        inspectedTracks: inspectedTracks,
                        into: &importedTracks,
                        metadata: &importedMetadata
                    )
                }
                continue
            }

            if ZipArchiveSupport.canHandle(url) {
                let entries =
                    (try? ZipArchiveSupport.listPlayableEntries(
                        in: url,
                        supportedExtensions: SPCFileScanner.supportedExtensions
                    )) ?? []
                for entry in entries {
                    let inspectedTracks = await inspectPlayableTracks(forArchiveEntry: entry)
                    merge(
                        inspectedTracks: inspectedTracks,
                        into: &importedTracks,
                        metadata: &importedMetadata
                    )
                }
                continue
            }

            if url.pathExtension.lowercased() == "m3u" {
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    continue
                }
                let tracks = PlaylistM3UCodec.decode(
                    contents,
                    baseDirectory: url.deletingLastPathComponent(),
                    supportedExtensions: SPCFileScanner.supportedExtensions
                )
                merge(
                    inspectedTracks: tracks.map { InspectedTrack(track: $0, metadata: emptyMetadata()) },
                    into: &importedTracks,
                    metadata: &importedMetadata
                )
                continue
            }

            guard SPCFileScanner.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }

            let inspectedTracks = await inspectPlayableTracks(forFileURL: url)
            merge(
                inspectedTracks: inspectedTracks,
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
            .filter { SPCFileScanner.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func inspectPlayableTracks(forFileURL fileURL: URL) async -> [InspectedTrack] {
        if let inspectedTracks = try? await PlaybackEngine.inspectPlayableTracks(fileURL: fileURL),
           !inspectedTracks.isEmpty {
            return inspectedTracks
        }

        return [
            InspectedTrack(track: TrackItem(url: fileURL), metadata: emptyMetadata())
        ]
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

        if let inspectedTracks = try? await PlaybackEngine.inspectPlayableTracks(fileURL: materializedURL),
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
