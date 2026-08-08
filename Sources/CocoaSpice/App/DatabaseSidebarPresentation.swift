import Foundation

enum DatabaseSidebarPresentation {
    private static let scanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func selectionStatusText(for item: DatabaseGameItem) -> String {
        "\(item.displayName) • \(item.trackCount) track\(item.trackCount == 1 ? "" : "s")"
    }

    static func disambiguateGameItems(_ items: [DatabaseGameItem]) -> [DatabaseGameItem] {
        let duplicateNames = Set(
            Dictionary(grouping: items, by: \.name)
                .filter { $0.value.count > 1 }
                .keys
        )

        return items.map { item in
            guard duplicateNames.contains(item.name) else { return item }
            let detail = item.systemName.isEmpty ? "Unknown System" : item.systemName
            return DatabaseGameItem(
                name: item.name,
                systemName: item.systemName,
                trackCount: item.trackCount,
                displayName: "\(item.name) (\(detail))"
            )
        }
    }

    static func scanRootStatusText(_ root: LibraryScanRoot, order: Int) -> String {
        if let error = root.lastScanError, !error.isEmpty {
            return error
        }

        if let lastScanCompletedAt = root.lastScanCompletedAt {
            let count = root.lastScanTrackCount == 0 ? "0 Files" : "\(root.lastScanTrackCount) Files"
            return "Last Scan \(scanDateFormatter.string(from: lastScanCompletedAt)) • \(count)"
        }

        return "Not scanned"
    }
}

/// Caches prefix-search candidates for the Games sidebar. The input field is
/// already debounced; this prevents each successive keystroke from rescanning
/// the complete game list.
struct DatabaseGameSearchIndex {
    private let items: [DatabaseGameItem]
    private var previousTerms: [String] = []
    private var previousMatches: [Int] = []

    init(items: [DatabaseGameItem] = []) {
        self.items = items
        self.previousMatches = Array(items.indices)
    }

    mutating func items(matching query: String) -> [DatabaseGameItem] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !terms.isEmpty else {
            previousTerms = []
            previousMatches = Array(items.indices)
            return items
        }

        let candidates = terms.starts(with: previousTerms)
            ? previousMatches
            : Array(items.indices)
        let matches = candidates.filter { index in
            terms.allSatisfy { items[index].searchableName.contains($0) }
        }
        previousTerms = terms
        previousMatches = matches
        return matches.map { items[$0] }
    }
}
