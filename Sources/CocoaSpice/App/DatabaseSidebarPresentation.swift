import CatalogBrowserCore
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
    private var sharedIndex: CatalogSearchIndex

    init(items: [DatabaseGameItem] = []) {
        self.items = items
        self.sharedIndex = CatalogSearchIndex(searchValues: items.map {
            "\($0.name) \($0.systemName) \($0.rootDisplayName) \($0.displayName)"
        })
    }

    mutating func items(matching query: String) -> [DatabaseGameItem] {
        sharedIndex.matchingIndices(query: query).compactMap { position in
            items.indices.contains(position) ? items[position] : nil
        }
    }
}
