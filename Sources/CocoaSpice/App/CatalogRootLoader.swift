import CatalogReader
import Foundation

/// Narrow read-only adapter for catalog roots and stored sidebar projections.
/// Playlist activation uses the shared CatalogReader projection so the native
/// and WebKit frontends consume the same root/game/system selection semantics.
enum CatalogBrowser {
    static func roots(databaseURL: URL) throws -> [CatalogRoot] {
        try ReadOnlyCatalog(databaseURL: databaseURL).roots().map {
            CatalogRoot(
                id: $0.id,
                path: $0.path,
                isEnabled: $0.isEnabled,
                trackCount: $0.trackCount
            )
        }
    }

    static func gameItems(
        databaseURL: URL,
        preferFoldersOverMetadata: Bool = true
    ) throws -> [DatabaseGameItem] {
        let catalog = try ReadOnlyCatalog(databaseURL: databaseURL)
        let items = try catalog.gameBuckets(preferFoldersOverMetadata: preferFoldersOverMetadata).map { bucket in
            let name = bucket.game.trimmingCharacters(in: .whitespacesAndNewlines)
            return DatabaseGameItem(
                rootID: bucket.rootID,
                rootPath: bucket.rootPath,
                name: name.isEmpty ? "Unknown Game" : name,
                systemName: bucket.system,
                trackCount: bucket.trackCount
            )
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
            DatabaseFileItem(
                rootID: bucket.rootID,
                rootPath: bucket.rootPath,
                folderPath: bucket.folderPath,
                path: bucket.path,
                isArchive: bucket.isArchive,
                trackCount: bucket.trackCount
            )
        }
    }
}
