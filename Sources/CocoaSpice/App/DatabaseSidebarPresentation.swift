import Foundation

enum DatabaseSidebarPresentation {
    static func selectionStatusText(for item: DatabaseGameItem) -> String {
        "\(item.displayName) • \(item.trackCount) track\(item.trackCount == 1 ? "" : "s")"
    }

    static func disambiguateGameItems(_ items: [DatabaseGameItem]) -> [DatabaseGameItem] {
        let duplicateNames = Set(
            Dictionary(grouping: items, by: \.name)
                .filter { $0.value.count > 1 }
                .keys
        )
        let duplicateBuckets = Set(
            Dictionary(grouping: items, by: { "\($0.name)\u{1F}\($0.systemName)" })
                .filter { $0.value.count > 1 }
                .keys
        )

        return items.map { item in
            let bucket = "\(item.name)\u{1F}\(item.systemName)"
            guard duplicateNames.contains(item.name) else { return item }
            let detail = item.systemName.isEmpty ? "Unknown System" : item.systemName
            let sourceDetail = duplicateBuckets.contains(bucket) ? " • \(item.rootDisplayName)" : ""
            return DatabaseGameItem(
                rootID: item.rootID,
                rootPath: item.rootPath,
                name: item.name,
                systemName: item.systemName,
                trackCount: item.trackCount,
                displayName: "\(item.name) (\(detail)\(sourceDetail))"
            )
        }
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
