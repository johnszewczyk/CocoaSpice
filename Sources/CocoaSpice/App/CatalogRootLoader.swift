import CatalogReader
import CatalogBrowserCore
import CatalogSessionCore
import Foundation

/// Narrow read-only adapter for catalog roots and stored sidebar projections.
/// Playlist activation uses the shared CatalogReader projection so the native
/// and WebKit frontends consume the same root/game/system selection semantics.
enum CatalogBrowser {
    static func databaseGameItems(from buckets: [CatalogGameBucket]) -> [DatabaseGameItem] {
        CatalogBrowserProjection.games(from: buckets).map { game in
            DatabaseGameItem(
                rootID: game.rootID,
                rootPath: game.rootPath,
                name: game.name,
                systemName: game.system,
                trackCount: game.trackCount,
                displayName: game.displayName
            )
        }
    }

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
        databaseGameItems(from: try CatalogSidebarReader.gameBuckets(
            databaseURL: databaseURL,
            preferFoldersOverMetadata: preferFoldersOverMetadata
        ))
    }

    static func fileItems(databaseURL: URL) throws -> [DatabaseFileItem] {
        return try CatalogSidebarReader.fileBuckets(databaseURL: databaseURL).map { bucket in
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
