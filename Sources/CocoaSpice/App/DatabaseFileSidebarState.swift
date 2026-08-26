import Foundation
import Observation
import CatalogBrowserCore
import CatalogReader

@MainActor
@Observable
final class DatabaseFileSidebarState {
    private(set) var searchText = ""
    private(set) var fileItems: [DatabaseFileItem] = []
    private(set) var visibleFileItems: [DatabaseFileItem] = []
    private var treeIndex: DatabaseFileSidebarTree.Index?
    private var filteredTreeIndex: DatabaseFileSidebarTree.Index?
    @ObservationIgnored private(set) var searchIndex: DatabaseFileSidebarTree.SearchIndex?
    @ObservationIgnored private var rootPaths: [Int64: String] = [:]
    private(set) var contentRevision = 0
    var selectedFileID: String?
    var selectedFileIDs: Set<String> = []
    var selectedFolders: Set<DatabaseFileSidebarFolder> = []
    var expandedFolderIDs: Set<String> = []
    private var expandedFolderIDsBeforeSearch: Set<String>?

    var allFolderIDs: Set<String> {
        if let filteredTreeIndex { return filteredTreeIndex.allFolderIDs }
        if let treeIndex { return treeIndex.allFolderIDs }
        return Set(DatabaseFileSidebarTree.rootFolderIDs(for: visibleFileItems))
    }

    func replaceFileItems(_ items: [DatabaseFileItem]) {
        installFileItems(items, treeIndex: nil, searchIndex: nil)
    }

    func replaceFileItems(_ items: [DatabaseFileItem], treeIndex: DatabaseFileSidebarTree.Index) {
        installFileItems(items, treeIndex: treeIndex, searchIndex: nil)
    }

    func replaceFileItems(
        _ items: [DatabaseFileItem],
        treeIndex: DatabaseFileSidebarTree.Index,
        searchIndex: DatabaseFileSidebarTree.SearchIndex
    ) {
        installFileItems(items, treeIndex: treeIndex, searchIndex: searchIndex)
    }

    private func installFileItems(
        _ items: [DatabaseFileItem],
        treeIndex: DatabaseFileSidebarTree.Index?,
        searchIndex: DatabaseFileSidebarTree.SearchIndex?
    ) {
        fileItems = items
        // Each root has many source rows. Retain one canonical root path
        // without assuming the input is unique by root ID.
        rootPaths = [:]
        rootPaths.reserveCapacity(items.count)
        for item in items where rootPaths[item.rootID] == nil {
            rootPaths[item.rootID] = item.rootPath
        }
        self.treeIndex = treeIndex
        self.searchIndex = searchIndex
        filteredTreeIndex = nil
        searchText = ""
        visibleFileItems = items
        expandedFolderIDsBeforeSearch = nil
        expandedFolderIDs.formIntersection(Set(DatabaseFileSidebarTree.rootFolderIDs(for: items)))
        if let selectedFileID,
           !items.contains(where: { $0.id == selectedFileID }) {
            clearSelection()
        }
        contentRevision &+= 1
    }

    func clear() {
        fileItems = []
        visibleFileItems = []
        treeIndex = nil
        filteredTreeIndex = nil
        searchIndex = nil
        rootPaths = [:]
        searchText = ""
        expandedFolderIDs = []
        expandedFolderIDsBeforeSearch = nil
        contentRevision &+= 1
        clearSelection()
    }

    func clearSelection() {
        selectedFileID = nil
        selectedFileIDs = []
        selectedFolders = []
    }

    func toggleFolder(_ folderID: String) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }

    func expandFolder(_ folderID: String) {
        expandedFolderIDs.insert(folderID)
    }

    func setAllFoldersCollapsed(_ collapsed: Bool) {
        expandedFolderIDs = collapsed ? [] : allFolderIDs
    }

    func folder(forID folderID: String) -> DatabaseFileSidebarFolder? {
        guard let separator = folderID.firstIndex(of: "|"),
              let rootID = Int64(folderID[..<separator]),
              let rootPath = rootPaths[rootID] else {
            return nil
        }
        let path = String(folderID[folderID.index(after: separator)...])
        return DatabaseFileSidebarFolder(rootID: rootID, rootPath: rootPath, path: path)
    }

    func rows() -> [DatabaseFileSidebarTree.Row] {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let treeIndex else {
            if let filteredTreeIndex {
                return filteredTreeIndex.rows(expandedFolderIDs: expandedFolderIDs)
            }
            return DatabaseFileSidebarTree.rows(items: visibleFileItems, expandedFolderIDs: expandedFolderIDs)
        }
        return treeIndex.rows(expandedFolderIDs: expandedFolderIDs)
    }

    func applySearchResult(
        query: String,
        items: [DatabaseFileItem],
        treeIndex: DatabaseFileSidebarTree.Index?
    ) {
        let wasSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Switching back to Files with an unchanged empty search must leave
        // the cached tree and its table rows intact. Otherwise each view
        // switch looks like new content and triggers a full table reload.
        guard wasSearching || isSearching else { return }
        if isSearching, !wasSearching {
            expandedFolderIDsBeforeSearch = expandedFolderIDs
        }
        searchText = query
        visibleFileItems = items
        filteredTreeIndex = treeIndex
        if isSearching, let treeIndex {
            // Search is a result view, not a second folder-navigation mode:
            // every matching ancestor is open so results are immediately
            // visible. Manual disclosure state returns when search clears.
            expandedFolderIDs = treeIndex.allFolderIDs
        } else if !isSearching, let expandedFolderIDsBeforeSearch {
            self.expandedFolderIDs = expandedFolderIDsBeforeSearch
            self.expandedFolderIDsBeforeSearch = nil
        }
        contentRevision &+= 1
    }
}

enum DatabaseFileSidebarTree {
    enum Row: Hashable {
        case folder(id: String, title: String, depth: Int, isExpanded: Bool)
        case file(DatabaseFileItem, depth: Int)

        var file: DatabaseFileItem? {
            guard case .file(let item, _) = self else { return nil }
            return item
        }
    }

    static func rootFolderIDs(for items: [DatabaseFileItem]) -> [String] {
        CatalogFileTreeIndex.rootFolderIDs(for: items.map { catalogBucket($0) })
    }

    static func folderID(rootID: Int64, path: String) -> String {
        CatalogFileTreeIndex.folderID(rootID: rootID, path: path)
    }

    static func filter(_ items: [DatabaseFileItem], query: String) -> [DatabaseFileItem] {
        filter(items, query: query, isCancelled: { false }) ?? []
    }

    static func filter(
        _ items: [DatabaseFileItem],
        query: String,
        isCancelled: @Sendable () -> Bool
    ) -> [DatabaseFileItem]? {
        let result = CatalogFileSearchIndex(files: items.map { catalogBucket($0) })
            .matchingFiles(query: query, isCancelled: isCancelled)
        return result?.map(Self.databaseItem)
    }

    /// Compatibility adapter for the native sidebar model. The searchable
    /// values and cancellation policy belong to CatalogBrowserCore; this
    /// wrapper only converts shared source buckets back into CS rows.
    struct SearchIndex: Sendable {
        private let sharedIndex: CatalogFileSearchIndex

        init(items: [DatabaseFileItem]) {
            sharedIndex = CatalogFileSearchIndex(files: items.map { DatabaseFileSidebarTree.catalogBucket($0) })
        }

        func filter(query: String, isCancelled: @Sendable () -> Bool) -> [DatabaseFileItem]? {
            sharedIndex.matchingFiles(query: query, isCancelled: isCancelled)?.map(DatabaseFileSidebarTree.databaseItem)
        }
    }

    /// Compatibility adapter for the native row enum. Graph construction,
    /// stable folder identity, ordering, and row flattening are shared.
    struct Index: Sendable {
        private let sharedIndex: CatalogFileTreeIndex
        private let itemsByID: [String: DatabaseFileItem]

        init(items: [DatabaseFileItem]) {
            self.init(items: items, isCancelled: { false })!
        }

        init?(items: [DatabaseFileItem], isCancelled: @Sendable () -> Bool) {
            guard let sharedIndex = CatalogFileTreeIndex(
                files: items.map { DatabaseFileSidebarTree.catalogBucket($0) },
                isCancelled: isCancelled
            ) else { return nil }
            self.sharedIndex = sharedIndex
            self.itemsByID = Dictionary(uniqueKeysWithValues: items.map { (DatabaseFileSidebarTree.itemID(rootID: $0.rootID, path: $0.path), $0) })
        }

        var allFolderIDs: Set<String> {
            sharedIndex.allFolderIDs
        }

        func rows(expandedFolderIDs: Set<String>) -> [Row] {
            sharedIndex.rows(expandedFolderIDs: expandedFolderIDs).compactMap { row in
                switch row {
                case .folder(let id, let title, let depth, let isExpanded):
                    return .folder(id: id, title: title, depth: depth, isExpanded: isExpanded)
                case .file(let file, let depth):
                    guard let item = itemsByID[DatabaseFileSidebarTree.itemID(rootID: file.rootID, path: file.path)] else { return nil }
                    return .file(item, depth: depth)
                }
            }
        }
    }

    static func rows(items: [DatabaseFileItem], expandedFolderIDs: Set<String>) -> [Row] {
        Index(items: items).rows(expandedFolderIDs: expandedFolderIDs)
    }

    private static func catalogBucket(_ item: DatabaseFileItem) -> CatalogFileBucket {
        CatalogFileBucket(
            rootID: item.rootID,
            rootPath: item.rootPath,
            folderPath: item.folderPath,
            path: item.path,
            isArchive: item.isArchive,
            trackCount: item.trackCount
        )
    }

    private static func itemID(rootID: Int64, path: String) -> String {
        "\(rootID)|\(path)"
    }

    private static func databaseItem(_ file: CatalogFileBucket) -> DatabaseFileItem {
        DatabaseFileItem(
            rootID: file.rootID,
            rootPath: file.rootPath,
            folderPath: file.folderPath,
            path: file.path,
            isArchive: file.isArchive,
            trackCount: file.trackCount
        )
    }
}
