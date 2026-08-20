import Foundation

enum PlaylistPresentation {
    static func titleText(for track: TrackItem, metadata: TrackMetadata?) -> String {
        metadata?.song.nonEmpty ?? track.displayName
    }

    static func gameText(for track: TrackItem, metadata: TrackMetadata?) -> String {
        metadata?.game.nonEmpty ?? track.groupDisplayName
    }

    static func authorText(for metadata: TrackMetadata?) -> String {
        metadata?.author.nonEmpty ?? "—"
    }

    static func systemText(for metadata: TrackMetadata?) -> String {
        metadata?.system.nonEmpty ?? "—"
    }

    static func lengthText(for metadata: TrackMetadata?) -> String {
        guard let metadata else { return "—" }
        let seconds = max(0, metadata.playLengthMs > 0 ? metadata.playLengthMs / 1000 : 0)
        guard seconds > 0 else { return "—" }
        return formatTime(seconds)
    }

    static func filterTracks(
        _ tracks: [TrackItem],
        metadata: [String: TrackMetadata],
        query: String
    ) -> [TrackItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return tracks }

        let terms = trimmedQuery.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return tracks.filter { track in
            let trackMetadata = metadata[track.id]
            let haystack = [
                track.filename,
                titleText(for: track, metadata: trackMetadata),
                gameText(for: track, metadata: trackMetadata),
                authorText(for: trackMetadata),
                systemText(for: trackMetadata)
            ]
            .joined(separator: " ")
            .lowercased()

            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    static func buildColumnWidthHints(
        tracks: [TrackItem],
        metadata: [String: TrackMetadata]
    ) -> PlaylistColumnWidthHints {
        var widestFileText = ""
        var widestTitleText = ""
        var widestGameText = ""
        var widestAuthorText = ""
        var widestSystemText = ""
        var widestLengthText = "—"

        for track in tracks {
            let trackMetadata = metadata[track.id]
            widestFileText = longerText(widestFileText, track.filename)
            widestTitleText = longerText(widestTitleText, titleText(for: track, metadata: trackMetadata))
            widestGameText = longerText(widestGameText, gameText(for: track, metadata: trackMetadata))
            widestAuthorText = longerText(widestAuthorText, authorText(for: trackMetadata))
            widestSystemText = longerText(widestSystemText, systemText(for: trackMetadata))
            widestLengthText = longerText(widestLengthText, lengthText(for: trackMetadata))
        }

        return PlaylistColumnWidthHints(
            indexText: String(max(1, tracks.count)),
            fileText: widestFileText,
            titleText: widestTitleText,
            gameText: widestGameText,
            authorText: widestAuthorText,
            systemText: widestSystemText,
            lengthText: widestLengthText
        )
    }

    static func compareTracks(
        _ lhs: TrackItem,
        _ rhs: TrackItem,
        by column: PlayerViewModel.PlaylistSortColumn,
        manualOrder: [String: Int],
        metadata: [String: TrackMetadata]
    ) -> ComparisonResult {
        let lhsMetadata = metadata[lhs.id]
        let rhsMetadata = metadata[rhs.id]

        switch column {
        case .index:
            return compare(manualOrder[lhs.id] ?? .max, manualOrder[rhs.id] ?? .max)
        case .file:
            return compare(lhs.filename, rhs.filename)
        case .title:
            return compare(titleText(for: lhs, metadata: lhsMetadata), titleText(for: rhs, metadata: rhsMetadata))
        case .game:
            return compare(gameText(for: lhs, metadata: lhsMetadata), gameText(for: rhs, metadata: rhsMetadata))
        case .author:
            return compare(authorText(for: lhsMetadata), authorText(for: rhsMetadata))
        case .system:
            return compare(systemText(for: lhsMetadata), systemText(for: rhsMetadata))
        case .path:
            return compare(lhs.fullPathText, rhs.fullPathText)
        case .length:
            return compare(lhsMetadata?.playLengthMs ?? 0, rhsMetadata?.playLengthMs ?? 0)
        }
    }

    static func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedStandardCompare(rhs)
    }

    private static func compare(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private static func longerText(_ lhs: String, _ rhs: String) -> String {
        lhs.count >= rhs.count ? lhs : rhs
    }
}
