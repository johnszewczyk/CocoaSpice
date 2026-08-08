import Observation

@MainActor
@Observable
final class DatabaseSidebarState {
    var searchText = "" {
        didSet {
            refreshVisibleItems()
        }
    }
    private(set) var gameItems: [DatabaseGameItem] = []
    private(set) var visibleGameItems: [DatabaseGameItem] = []
    private var searchIndex = DatabaseGameSearchIndex()
    private(set) var contentRevision = 0
    var selectedGameID: String?
    var selectedGameIDs: Set<String> = []

    func replaceGameItems(_ items: [DatabaseGameItem]) {
        gameItems = items
        searchIndex = DatabaseGameSearchIndex(items: items)
        if let selectedGameID,
           !items.contains(where: { $0.id == selectedGameID }) {
            clearSelection()
        }
        refreshVisibleItems()
    }

    func clear() {
        gameItems = []
        visibleGameItems = []
        searchIndex = DatabaseGameSearchIndex()
        contentRevision &+= 1
        clearSelection()
    }

    func clearSelection() {
        selectedGameID = nil
        selectedGameIDs = []
    }

    private func refreshVisibleItems() {
        visibleGameItems = searchIndex.items(matching: searchText)
        contentRevision &+= 1
    }
}
