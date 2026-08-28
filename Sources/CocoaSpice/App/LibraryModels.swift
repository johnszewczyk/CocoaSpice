import Foundation

/// A root published in the read-only ScanSong catalog.
struct CatalogRoot: Identifiable, Equatable {
    let id: Int64
    let path: String
    let isEnabled: Bool
    let trackCount: Int

    var standardizedURL: URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }
}

struct DatabaseFileItem: Identifiable, Hashable, Sendable {
    let rootID: Int64
    let rootPath: String
    let folderPath: String
    let path: String
    let isArchive: Bool
    let trackCount: Int

    var id: String {
        "\(rootID)|\(path)"
    }

    var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

/// A consistent database snapshot for the Games and Files sidebar modes.
struct DatabaseSidebarContent: Sendable, Equatable {
    let gameItems: [DatabaseGameItem]
    let fileItems: [DatabaseFileItem]

    static let empty = DatabaseSidebarContent(gameItems: [], fileItems: [])
}

struct DatabaseFileSidebarFolder: Hashable, Codable, Sendable {
    let rootID: Int64
    let rootPath: String
    let path: String

    var id: String {
        DatabaseFileSidebarTree.folderID(rootID: rootID, path: path)
    }
}

struct DatabaseFileSidebarDragPayload: Codable {
    let fileIDs: [String]
    let folders: [DatabaseFileSidebarFolder]
}
