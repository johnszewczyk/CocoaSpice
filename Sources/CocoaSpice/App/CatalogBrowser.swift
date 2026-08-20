import CatalogReader
import Foundation

/// CocoaSpice's read-only view of a published catalog. It has no scanner,
/// decoder, schema migration, or write capability.
enum CatalogBrowser {
    static func roots(databaseURL: URL) throws -> [LibraryScanRoot] {
        try ReadOnlyCatalog(databaseURL: databaseURL).roots().map {
            LibraryScanRoot(
                id: $0.id,
                path: $0.path,
                isEnabled: $0.isEnabled,
                displayOrder: 0,
                lastScanStartedAt: nil,
                lastScanCompletedAt: nil,
                lastScanTrackCount: $0.trackCount,
                lastScanError: nil
            )
        }
    }

    static func gameItems(databaseURL: URL, preferFoldersOverMetadata: Bool = true) throws -> [DatabaseGameItem] {
        let catalog = try ReadOnlyCatalog(databaseURL: databaseURL)
        let items = try catalog.gameBuckets().map { bucket in
            let name = bucket.game.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Game" : bucket.game
            let displayName = ZipArchiveSupport.canHandle(URL(fileURLWithPath: name))
                ? URL(fileURLWithPath: name).lastPathComponent
                : nil
            return DatabaseGameItem(rootID: bucket.rootID, rootPath: bucket.rootPath, name: name, systemName: bucket.system, trackCount: bucket.trackCount, displayName: displayName)
        }
        return DatabaseSidebarPresentation.disambiguateGameItems(items).sorted {
            let name = $0.name.localizedCaseInsensitiveCompare($1.name)
            if name != .orderedSame { return name == .orderedAscending }
            let system = $0.systemName.localizedCaseInsensitiveCompare($1.systemName)
            if system != .orderedSame { return system == .orderedAscending }
            return $0.rootPath.localizedCaseInsensitiveCompare($1.rootPath) == .orderedAscending
        }
    }

    static func fileItems(databaseURL: URL) throws -> [DatabaseFileItem] {
        let catalog = try ReadOnlyCatalog(databaseURL: databaseURL)
        return try catalog.fileBuckets().map { bucket in
            return DatabaseFileItem(
                rootID: bucket.rootID,
                rootPath: bucket.rootPath,
                folderPath: bucket.folderPath,
                path: bucket.path,
                isArchive: bucket.isArchive,
                trackCount: bucket.trackCount
            )
        }
    }

    static func playlist(databaseURL: URL, games: [DatabaseGameItem] = [], files: [DatabaseFileItem] = [], folders: [DatabaseFileSidebarFolder] = [], paths: [String] = [], preferFoldersOverMetadata: Bool = true) throws -> LoadedPlaylistData {
        let catalog = try ReadOnlyCatalog(databaseURL: databaseURL)
        // A game selection is the common interactive case. Query its published
        // bucket directly; never fall back to a full-catalogue scan.
        if !games.isEmpty, files.isEmpty, folders.isEmpty, paths.isEmpty {
            let direct = try games.flatMap {
                try catalog.tracks(
                    rootID: $0.rootID,
                    game: $0.name,
                    system: $0.systemName,
                    preferFoldersOverMetadata: preferFoldersOverMetadata
                )
            }
            return makePlaylist(direct)
        }
        let selectedGames = Set(games.map { "\($0.rootID)\u{1F}\($0.name)\u{1F}\($0.systemName)" })
        let selectedFiles = Set(files.map { "\($0.rootID)\u{1F}\($0.path)" })
        let selectedPaths = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let selectedFolders = folders.map { (rootID: $0.rootID, path: URL(fileURLWithPath: $0.path, isDirectory: true).standardizedFileURL.path) }
        let selected = try catalog.tracks().filter { track in
            let gameMatch = selectedGames.contains(gameBucket(for: track, preferFoldersOverMetadata: preferFoldersOverMetadata))
            let fileMatch = selectedFiles.contains("\(track.rootID)\u{1F}\(track.sourcePath)")
            let folder = URL(fileURLWithPath: track.sourcePath).deletingLastPathComponent().standardizedFileURL.path
            let folderMatch = selectedFolders.contains { $0.rootID == track.rootID && (folder == $0.path || folder.hasPrefix($0.path + "/")) }
            return gameMatch || fileMatch || folderMatch || selectedPaths.contains(URL(fileURLWithPath: track.sourcePath).standardizedFileURL.path)
        }
        return makePlaylist(selected)
    }

    static func playlist(databaseURL: URL, rootPath: String, folderPath: String) throws -> LoadedPlaylistData {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true).standardizedFileURL.path
        let catalog = try ReadOnlyCatalog(databaseURL: databaseURL)
        let rootIDs = Set(try catalog.roots().filter {
            URL(fileURLWithPath: $0.path, isDirectory: true).standardizedFileURL.path == root
        }.map(\.id))
        return makePlaylist(try catalog.tracks().filter {
            let parent = URL(fileURLWithPath: $0.sourcePath).deletingLastPathComponent().standardizedFileURL.path
            return rootIDs.contains($0.rootID) && (parent == folder || parent.hasPrefix(folder + "/"))
        })
    }

    private static func makePlaylist(_ records: [CatalogTrack]) -> LoadedPlaylistData {
        let sorted = records.sorted { ($0.sourcePath, $0.archiveEntry ?? "", $0.trackIndex) < ($1.sourcePath, $1.archiveEntry ?? "", $1.trackIndex) }
        var tracks: [TrackItem] = []
        var metadata: [String: TrackMetadata] = [:]
        for record in sorted {
            let track = record.archiveEntry.map { TrackItem(archiveURL: URL(fileURLWithPath: record.archivePath ?? record.sourcePath), entryPath: $0, trackIndex: record.trackIndex, trackCount: record.trackCount) }
                ?? TrackItem(url: URL(fileURLWithPath: record.sourcePath), trackIndex: record.trackIndex, trackCount: record.trackCount)
            tracks.append(track)
            metadata[track.id] = TrackMetadata(game: record.game, song: record.title, system: record.system, author: record.author, comment: record.comment, introLengthMs: record.introLengthMilliseconds, loopLengthMs: record.loopLengthMilliseconds, playLengthMs: record.lengthMilliseconds, fadeLengthMs: record.fadeLengthMilliseconds)
        }
        return LoadedPlaylistData(tracks: tracks, metadata: metadata, widthHints: PlaylistColumnWidthHints(indexText: String(max(1, tracks.count)), fileText: tracks.map(\.filename).max(by: { $0.count < $1.count }) ?? "", titleText: records.map(\.title).max(by: { $0.count < $1.count }) ?? "", gameText: records.map(\.game).max(by: { $0.count < $1.count }) ?? "", authorText: records.map(\.author).max(by: { $0.count < $1.count }) ?? "", systemText: records.map(\.system).max(by: { $0.count < $1.count }) ?? "", lengthText: "—"))
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func gameBucket(for track: CatalogTrack, preferFoldersOverMetadata: Bool) -> String {
        let game = nonEmpty(track.browserGame) ?? nonEmpty(track.game)
            ?? URL(fileURLWithPath: track.sourcePath).deletingLastPathComponent().lastPathComponent
        let system = preferFoldersOverMetadata
            ? nonEmpty(track.browserSystem) ?? nonEmpty(track.system) ?? ""
            : nonEmpty(track.system) ?? nonEmpty(track.browserSystem) ?? ""
        return "\(track.rootID)\u{1F}\(game)\u{1F}\(system)"
    }
}
