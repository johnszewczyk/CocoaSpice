import Foundation
import PlaylistIdentityCore

enum TrackSource: Hashable, Sendable {
    case file(URL)
    case zipEntry(archiveURL: URL, entryPath: String)

    init(fileURL: URL) {
        self = .file(fileURL.standardizedFileURL)
    }

    init(archiveURL: URL, entryPath: String) {
        self = .zipEntry(
            archiveURL: archiveURL.standardizedFileURL,
            entryPath: Self.normalizeEntryPath(entryPath)
        )
    }

    var sourceURL: URL {
        switch self {
        case .file(let url):
            return url
        case .zipEntry(let archiveURL, _):
            return archiveURL
        }
    }

    var revealURL: URL {
        sourceURL
    }

    var persistentID: String {
        PlaylistTrackIdentity.sourceID(
            sourcePath: sourceURL.path,
            archiveEntry: archiveEntryPath
        )
    }

    var playablePathExtension: String {
        switch self {
        case .file(let url):
            return url.pathExtension.lowercased()
        case .zipEntry(_, let entryPath):
            return URL(fileURLWithPath: entryPath).pathExtension.lowercased()
        }
    }

    var leafFilename: String {
        switch self {
        case .file(let url):
            return url.lastPathComponent
        case .zipEntry(_, let entryPath):
            return URL(fileURLWithPath: entryPath).lastPathComponent
        }
    }

    var displayBaseName: String {
        switch self {
        case .file(let url):
            return FilenamePresentation.withoutDisplayedExtension(url.lastPathComponent)
        case .zipEntry(_, let entryPath):
            return FilenamePresentation.withoutDisplayedExtension(
                URL(fileURLWithPath: entryPath).lastPathComponent
            )
        }
    }

    var groupDisplayName: String {
        switch self {
        case .file(let url):
            let folderName = url.deletingLastPathComponent().lastPathComponent
            return folderName.isEmpty ? url.lastPathComponent : folderName
        case .zipEntry(let archiveURL, _):
            return archiveURL.lastPathComponent
        }
    }

    var relativeSourcePath: String {
        switch self {
        case .file:
            return leafFilename
        case .zipEntry(_, let entryPath):
            return entryPath
        }
    }

    var fullSourcePath: String {
        switch self {
        case .file(let url):
            return url.path
        case .zipEntry(let archiveURL, let entryPath):
            return "\(archiveURL.path)#\(entryPath)"
        }
    }

    var isArchiveEntry: Bool {
        if case .zipEntry = self {
            return true
        }
        return false
    }

    var archiveEntryPath: String? {
        if case .zipEntry(_, let entryPath) = self {
            return entryPath
        }
        return nil
    }

    private static func normalizeEntryPath(_ entryPath: String) -> String {
        entryPath
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }
}

enum FilenamePresentation {
    private static let compoundArchiveSuffixes = [
        ".tar.zst", ".tar.zstd", ".tar.gz", ".tar.bz2", ".tar.xz", ".tar.lz", ".tar.lz4"
    ]

    static func withoutDisplayedExtension(_ filename: String) -> String {
        let lowercased = filename.lowercased()
        if let suffix = compoundArchiveSuffixes.first(where: { lowercased.hasSuffix($0) }) {
            return String(filename.dropLast(suffix.count))
        }
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        return stem.isEmpty ? filename : stem
    }
}

struct SidebarFolder: Identifiable, Hashable {
    let url: URL
    let hasChildren: Bool

    var id: String { url.path }
    var displayName: String { url.lastPathComponent }
}

enum SidebarSearchItemKind: String, Hashable, Sendable {
    case folder
    case track
}

struct SidebarSearchItem: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: SidebarSearchItemKind
    let track: TrackItem?
    let primaryTextOverride: String?
    let secondaryTextOverride: String?

    init(url: URL, kind: SidebarSearchItemKind, track: TrackItem? = nil, primaryTextOverride: String? = nil, secondaryTextOverride: String? = nil) {
        self.url = url
        self.kind = kind
        self.track = track
        self.primaryTextOverride = primaryTextOverride
        self.secondaryTextOverride = secondaryTextOverride
    }

    var id: String {
        if let track {
            return "\(kind.rawValue):\(track.id)"
        }
        return "\(kind.rawValue):\(url.path)"
    }
    var displayName: String {
        if let track {
            return track.displayName
        }
        return url.lastPathComponent
    }
    var primaryText: String { primaryTextOverride ?? displayName }
    var secondaryText: String { secondaryTextOverride ?? url.deletingLastPathComponent().lastPathComponent }
    var parentPath: String { url.deletingLastPathComponent().path }
}

struct DatabaseGameItem: Identifiable, Hashable, Sendable {
    let rootID: Int64
    let rootPath: String
    let name: String
    let systemName: String
    let trackCount: Int
    let displayName: String
    let searchableName: String

    var id: String { "\(rootID)\u{1F}\(name)\u{1F}\(systemName)" }
    var rootDisplayName: String {
        URL(fileURLWithPath: rootPath, isDirectory: true).lastPathComponent
    }

    init(rootID: Int64, rootPath: String, name: String, systemName: String = "", trackCount: Int, displayName: String? = nil) {
        self.rootID = rootID
        self.rootPath = rootPath
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.systemName = systemName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trackCount = trackCount
        self.displayName = (displayName ?? self.name).trimmingCharacters(in: .whitespacesAndNewlines)
        let rootName = URL(fileURLWithPath: rootPath, isDirectory: true).lastPathComponent
        self.searchableName = "\(self.name) \(self.systemName) \(rootName)".lowercased()
    }
}

struct TrackItem: Identifiable, Hashable, Sendable {
    let source: TrackSource
    let trackIndex: Int
    let trackCount: Int

    init(url: URL, trackIndex: Int = 0, trackCount: Int = 1) {
        self.source = TrackSource(fileURL: url)
        self.trackIndex = max(0, trackIndex)
        self.trackCount = max(1, trackCount)
    }

    init(archiveURL: URL, entryPath: String, trackIndex: Int = 0, trackCount: Int = 1) {
        self.source = TrackSource(archiveURL: archiveURL, entryPath: entryPath)
        self.trackIndex = max(0, trackIndex)
        self.trackCount = max(1, trackCount)
    }

    var url: URL { source.sourceURL }
    var revealURL: URL { source.revealURL }
    var id: String {
        PlaylistTrackIdentity.trackID(
            sourcePath: url.path,
            archiveEntry: archiveEntryPath,
            trackIndex: trackIndex
        )
    }
    var containerID: String { source.persistentID }
    var displayTrackNumber: Int { trackIndex + 1 }
    var isMultiTrackContainer: Bool { trackCount > 1 }
    var isArchiveEntry: Bool { source.isArchiveEntry }
    var archiveEntryPath: String? { source.archiveEntryPath }
    var playablePathExtension: String { source.playablePathExtension }
    var groupDisplayName: String { source.groupDisplayName }
    var relativeSourcePath: String { source.relativeSourcePath }
    var filename: String {
        if isMultiTrackContainer {
            return "\(source.leafFilename) [\(displayTrackNumber)]"
        }
        return source.leafFilename
    }
    var displayName: String {
        let baseName = source.displayBaseName
        if isMultiTrackContainer {
            return "\(baseName) [\(displayTrackNumber)]"
        }
        return baseName
    }
    var statusPathText: String {
        if isMultiTrackContainer {
            return "\(groupDisplayName)\\\(relativeSourcePath) [\(displayTrackNumber)]"
        }
        return "\(groupDisplayName)\\\(relativeSourcePath)"
    }
    var fullPathText: String {
        let trackSuffix = isMultiTrackContainer ? " [\(displayTrackNumber)]" : ""
        return "\(source.fullSourcePath)\(trackSuffix)"
    }

    static func expanded(url: URL, trackCount: Int) -> [TrackItem] {
        let count = max(1, trackCount)
        return (0..<count).map { TrackItem(url: url, trackIndex: $0, trackCount: count) }
    }

    static func expanded(
        archiveURL: URL,
        entryPath: String,
        trackCount: Int
    ) -> [TrackItem] {
        let count = max(1, trackCount)
        return (0..<count).map {
            TrackItem(
                archiveURL: archiveURL,
                entryPath: entryPath,
                trackIndex: $0,
                trackCount: count
            )
        }
    }
    var persistedValue: String {
        let payload = PersistedTrackItem(
            kind: isArchiveEntry ? "zipEntry" : "file",
            path: url.path,
            entryPath: archiveEntryPath,
            trackIndex: trackIndex,
            trackCount: trackCount
        )
        guard let data = try? JSONEncoder().encode(payload),
              let encoded = String(data: data, encoding: .utf8) else {
            return url.path
        }
        return encoded
    }

    static func fromPersistedValue(_ value: String) -> TrackItem? {
        if let data = value.data(using: .utf8),
           let payload = try? JSONDecoder().decode(PersistedTrackItem.self, from: data) {
            if payload.kind == "zipEntry", let entryPath = payload.entryPath {
                return TrackItem(
                    archiveURL: URL(fileURLWithPath: payload.path),
                    entryPath: entryPath,
                    trackIndex: payload.trackIndex,
                    trackCount: payload.trackCount
                )
            }
            return TrackItem(
                url: URL(fileURLWithPath: payload.path),
                trackIndex: payload.trackIndex,
                trackCount: payload.trackCount
            )
        }

        guard value.hasPrefix("/") else { return nil }
        return TrackItem(url: URL(fileURLWithPath: value))
    }

    static func == (lhs: TrackItem, rhs: TrackItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct PersistedTrackItem: Codable {
    let kind: String?
    let path: String
    let entryPath: String?
    let trackIndex: Int
    let trackCount: Int
}

struct PlaylistColumnWidthHints: Equatable, Sendable {
    let indexText: String
    let fileText: String
    let titleText: String
    let gameText: String
    let authorText: String
    let systemText: String
    let lengthText: String
}

extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
