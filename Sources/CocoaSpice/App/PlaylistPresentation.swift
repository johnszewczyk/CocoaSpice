import CatalogPlaylistPresentationCore
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
        by column: CatalogPlaylistSortColumn,
        manualOrder: [String: Int],
        metadata: [String: TrackMetadata]
    ) -> ComparisonResult {
        CatalogPlaylistSorting.compare(
            sortRecord(for: lhs, manualOrder: manualOrder, metadata: metadata[lhs.id]),
            sortRecord(for: rhs, manualOrder: manualOrder, metadata: metadata[rhs.id]),
            by: column
        )
    }

    static func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func sortRecord(
        for track: TrackItem,
        manualOrder: [String: Int],
        metadata: TrackMetadata?
    ) -> CatalogPlaylistSortRecord {
        CatalogPlaylistSortRecord(
            id: track.id,
            naturalOrder: manualOrder[track.id] ?? .max,
            fileText: track.filename,
            titleText: titleText(for: track, metadata: metadata),
            gameText: gameText(for: track, metadata: metadata),
            authorText: authorText(for: metadata),
            systemText: systemText(for: metadata),
            pathText: track.fullPathText,
            lengthMilliseconds: metadata?.playLengthMs ?? 0
        )
    }

    private static func longerText(_ lhs: String, _ rhs: String) -> String {
        lhs.count >= rhs.count ? lhs : rhs
    }
}
