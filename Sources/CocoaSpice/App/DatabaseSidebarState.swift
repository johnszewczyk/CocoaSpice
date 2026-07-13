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
    var selectedGameID: String?
    var selectedGameIDs: Set<String> = []

    func replaceGameItems(_ items: [DatabaseGameItem]) {
        gameItems = items
        if let selectedGameID,
           !items.contains(where: { $0.id == selectedGameID }) {
            clearSelection()
        }
        refreshVisibleItems()
    }

    func clear() {
        gameItems = []
        visibleGameItems = []
        clearSelection()
    }

    func clearSelection() {
        selectedGameID = nil
        selectedGameIDs = []
    }

    private func refreshVisibleItems() {
        visibleGameItems = DatabaseSidebarPresentation.filterGameItems(
            gameItems,
            query: searchText
        )
    }
}
