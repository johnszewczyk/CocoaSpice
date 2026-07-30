import Foundation

struct LibraryScanRoot: Identifiable, Equatable {
    let id: Int64
    var path: String
    var isEnabled: Bool
    var displayOrder: Int
    var lastScanStartedAt: Date?
    var lastScanCompletedAt: Date?
    var lastScanTrackCount: Int
    var lastScanError: String?

    var standardizedURL: URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }
}

struct LibraryTrackRecord: Sendable {
    let rootID: Int64
    let folderPath: String
    let path: String
    let filename: String
    let fileExtension: String
    let trackIndex: Int
    let trackCount: Int
    let fileSize: Int64
    let modifiedAt: Date
    let archivePath: String?
    let archiveEntry: String?
    let metadata: TrackMetadata?
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
