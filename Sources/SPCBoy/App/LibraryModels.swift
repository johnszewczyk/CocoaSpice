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

struct LibraryTrackRecord {
    let rootID: Int64
    let folderPath: String
    let path: String
    let filename: String
    let fileExtension: String
    let trackIndex: Int
    let trackCount: Int
    let fileSize: Int64
    let modifiedAt: Date
    let metadata: TrackMetadata?
}
