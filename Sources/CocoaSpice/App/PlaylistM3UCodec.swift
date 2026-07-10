import Foundation

enum PlaylistM3UCodec {
    static func encode(_ tracks: [TrackItem]) -> String {
        var lines = ["#EXTM3U"]
        for track in tracks {
            lines.append("#COCOASPICE:\(track.persistedValue)")
            lines.append(track.url.path)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func decode(
        _ contents: String,
        baseDirectory: URL,
        fileManager: FileManager = .default,
        supportedExtensions: Set<String>
    ) -> [TrackItem] {
        var pendingPersistedTrack: TrackItem?
        var pendingTrackIndex = 0
        var pendingTrackCount = 1
        var tracks: [TrackItem] = []

        for rawLine in contents.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#COCOASPICE:") {
                let payload = String(line.dropFirst("#COCOASPICE:".count))
                if let persistedTrack = TrackItem.fromPersistedValue(payload) {
                    pendingPersistedTrack = persistedTrack
                    continue
                }
                for component in payload.split(separator: ";").map(String.init) {
                    let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { continue }
                    switch parts[0] {
                    case "trackIndex":
                        pendingTrackIndex = Int(parts[1]) ?? 0
                    case "trackCount":
                        pendingTrackCount = Int(parts[1]) ?? 1
                    default:
                        break
                    }
                }
                continue
            }

            guard !line.hasPrefix("#") else { continue }
            let resolvedURL: URL
            if line.hasPrefix("/") {
                resolvedURL = URL(fileURLWithPath: line)
            } else {
                resolvedURL = URL(fileURLWithPath: line, relativeTo: baseDirectory).standardizedFileURL
            }

            defer {
                pendingPersistedTrack = nil
                pendingTrackIndex = 0
                pendingTrackCount = 1
            }

            if let pendingPersistedTrack {
                let restoredTrack: TrackItem
                if let entryPath = pendingPersistedTrack.archiveEntryPath {
                    restoredTrack = TrackItem(
                        archiveURL: resolvedURL,
                        entryPath: entryPath,
                        trackIndex: pendingPersistedTrack.trackIndex,
                        trackCount: pendingPersistedTrack.trackCount
                    )
                } else {
                    restoredTrack = TrackItem(
                        url: resolvedURL,
                        trackIndex: pendingPersistedTrack.trackIndex,
                        trackCount: pendingPersistedTrack.trackCount
                    )
                }

                guard fileManager.fileExists(atPath: restoredTrack.url.path) else {
                    continue
                }

                if restoredTrack.isArchiveEntry || supportedExtensions.contains(restoredTrack.playablePathExtension) {
                    tracks.append(restoredTrack)
                }
                continue
            }

            guard fileManager.fileExists(atPath: resolvedURL.path),
                  supportedExtensions.contains(resolvedURL.pathExtension.lowercased()) else {
                continue
            }

            tracks.append(
                TrackItem(
                    url: resolvedURL,
                    trackIndex: pendingTrackIndex,
                    trackCount: pendingTrackCount
                )
            )
        }

        return tracks
    }
}
