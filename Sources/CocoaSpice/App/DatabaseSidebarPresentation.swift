import Foundation

enum DatabaseSidebarPresentation {
    static func selectionStatusText(for item: DatabaseGameItem) -> String {
        "\(item.displayName) • \(item.trackCount) track\(item.trackCount == 1 ? "" : "s")"
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
