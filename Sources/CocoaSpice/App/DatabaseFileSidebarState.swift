import Foundation
import Observation

@MainActor
@Observable
final class DatabaseFileSidebarState {
    private(set) var searchText = ""
    private(set) var fileItems: [DatabaseFileItem] = []
    private(set) var visibleFileItems: [DatabaseFileItem] = []
    private var treeIndex: DatabaseFileSidebarTree.Index?
    private var filteredTreeIndex: DatabaseFileSidebarTree.Index?
    private(set) var contentRevision = 0
    var selectedFileID: String?
    var selectedFileIDs: Set<String> = []
    var selectedFolders: Set<DatabaseFileSidebarFolder> = []
    var expandedFolderIDs: Set<String> = []

    func replaceFileItems(_ items: [DatabaseFileItem]) {
        installFileItems(items, treeIndex: nil)
    }

    func replaceFileItems(_ items: [DatabaseFileItem], treeIndex: DatabaseFileSidebarTree.Index) {
        installFileItems(items, treeIndex: treeIndex)
    }

    private func installFileItems(_ items: [DatabaseFileItem], treeIndex: DatabaseFileSidebarTree.Index?) {
        fileItems = items
        self.treeIndex = treeIndex
        filteredTreeIndex = nil
        searchText = ""
        visibleFileItems = items
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
        searchText = ""
        expandedFolderIDs = []
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
        searchText = query
        visibleFileItems = items
        filteredTreeIndex = treeIndex
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
        Array(Set(items.map { folderID(rootID: $0.rootID, path: $0.rootPath) }))
    }

    static func folderID(rootID: Int64, path: String) -> String {
        "\(rootID)|\(path)"
    }

    static func filter(_ items: [DatabaseFileItem], query: String) -> [DatabaseFileItem] {
        filter(items, query: query, isCancelled: { false }) ?? []
    }

    static func filter(
        _ items: [DatabaseFileItem],
        query: String,
        isCancelled: @Sendable () -> Bool
    ) -> [DatabaseFileItem]? {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items }
        var matches: [DatabaseFileItem] = []
        matches.reserveCapacity(min(items.count, 256))
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let haystack = "\(item.filename) \(item.folderPath) \(item.path)".lowercased()
            if terms.allSatisfy(haystack.contains) {
                matches.append(item)
            }
        }
        return isCancelled() ? nil : matches
    }

    /// Built once with the database read result, off the main actor. Folder
    /// disclosure then walks only the visible branch instead of rebuilding a
    /// complete path graph from every stored source file on each reload.
    struct Index: Sendable {
        private struct Folder: Sendable {
            let title: String
            let childFolderIDs: [String]
            let directFiles: [DatabaseFileItem]
        }

        private struct FolderBuilder {
            let rootID: Int64
            let path: String
            let title: String
            var childFolderIDs: Set<String> = []
            var directFiles: [DatabaseFileItem] = []
        }

        private let rootFolderIDs: [String]
        private let folders: [String: Folder]

        init(items: [DatabaseFileItem]) {
            self.init(items: items, isCancelled: { false })!
        }

        init?(items: [DatabaseFileItem], isCancelled: @Sendable () -> Bool) {
            var builders: [String: FolderBuilder] = [:]
            var rootIDs: Set<String> = []

            func title(for path: String) -> String {
                let title = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
                return title.isEmpty ? path : title
            }

            func ensureFolder(rootID: Int64, path: String) {
                let id = DatabaseFileSidebarTree.folderID(rootID: rootID, path: path)
                guard builders[id] == nil else { return }
                builders[id] = FolderBuilder(rootID: rootID, path: path, title: title(for: path))
            }

            for (index, item) in items.enumerated() {
                if index.isMultiple(of: 256), isCancelled() {
                    return nil
                }
                let rootID = item.rootID
                ensureFolder(rootID: rootID, path: item.rootPath)
                rootIDs.insert(DatabaseFileSidebarTree.folderID(rootID: rootID, path: item.rootPath))

                var folderPath = item.folderPath
                ensureFolder(rootID: rootID, path: folderPath)
                while folderPath != item.rootPath,
                      folderPath.hasPrefix(item.rootPath + "/") {
                    let parentPath = URL(fileURLWithPath: folderPath, isDirectory: true)
                        .deletingLastPathComponent()
                        .path
                    ensureFolder(rootID: rootID, path: parentPath)
                    let parentID = DatabaseFileSidebarTree.folderID(rootID: rootID, path: parentPath)
                    let childID = DatabaseFileSidebarTree.folderID(rootID: rootID, path: folderPath)
                    builders[parentID]?.childFolderIDs.insert(childID)
                    folderPath = parentPath
                }

                let folderID = DatabaseFileSidebarTree.folderID(rootID: rootID, path: item.folderPath)
                builders[folderID]?.directFiles.append(item)
            }

            var folders: [String: Folder] = [:]
            folders.reserveCapacity(builders.count)
            for (index, entry) in builders.enumerated() {
                if index.isMultiple(of: 64), isCancelled() {
                    return nil
                }
                let (id, builder) = entry
                let sortedFiles = builder.directFiles
                    .map { (item: $0, filename: DatabaseFileSidebarTree.filename(in: $0.path)) }
                    .sorted {
                        $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending
                    }
                    .map(\.item)
                folders[id] = Folder(
                    title: builder.title,
                    childFolderIDs: builder.childFolderIDs.sorted { lhs, rhs in
                        let lhsTitle = builders[lhs]?.title ?? lhs
                        let rhsTitle = builders[rhs]?.title ?? rhs
                        return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
                    },
                    directFiles: sortedFiles
                )
            }
            guard !isCancelled() else { return nil }
            self.folders = folders
            self.rootFolderIDs = rootIDs.sorted { lhs, rhs in
                let lhsPath = builders[lhs]?.path ?? lhs
                let rhsPath = builders[rhs]?.path ?? rhs
                return lhsPath.localizedCaseInsensitiveCompare(rhsPath) == .orderedAscending
            }
        }

        func rows(expandedFolderIDs: Set<String>) -> [Row] {
            var rows: [Row] = []

            func appendFolder(_ id: String, depth: Int) {
                guard let folder = folders[id] else { return }
                let isExpanded = expandedFolderIDs.contains(id)
                rows.append(.folder(id: id, title: folder.title, depth: depth, isExpanded: isExpanded))
                guard isExpanded else { return }

                for childID in folder.childFolderIDs {
                    appendFolder(childID, depth: depth + 1)
                }
                for file in folder.directFiles {
                    rows.append(.file(file, depth: depth + 1))
                }
            }

            for rootID in rootFolderIDs {
                appendFolder(rootID, depth: 0)
            }
            return rows
        }
    }

    static func rows(items: [DatabaseFileItem], expandedFolderIDs: Set<String>) -> [Row] {
        let groupedByRoot = Dictionary(grouping: items, by: \.rootID)
        return groupedByRoot.values
            .sorted { $0[0].rootPath.localizedCaseInsensitiveCompare($1[0].rootPath) == .orderedAscending }
            .flatMap { rootItems in
                rowsForRoot(items: rootItems, expandedFolderIDs: expandedFolderIDs)
            }
    }

    private static func rowsForRoot(
        items: [DatabaseFileItem],
        expandedFolderIDs: Set<String>
    ) -> [Row] {
        guard let first = items.first else { return [] }
        let rootID = first.rootID
        let rootPath = first.rootPath
        var directFiles: [String: [DatabaseFileItem]] = [:]
        var children: [String: Set<String>] = [:]

        for item in items {
            directFiles[item.folderPath, default: []].append(item)
            var childPath = item.folderPath
            while childPath != rootPath, childPath.hasPrefix(rootPath + "/") {
                let parentPath = URL(fileURLWithPath: childPath, isDirectory: true)
                    .deletingLastPathComponent()
                    .path
                children[parentPath, default: []].insert(childPath)
                childPath = parentPath
            }
        }

        func appendFolder(_ path: String, depth: Int, into rows: inout [Row]) {
            let id = folderID(rootID: rootID, path: path)
            let isExpanded = expandedFolderIDs.contains(id)
            let title = path == rootPath
                ? URL(fileURLWithPath: rootPath, isDirectory: true).lastPathComponent
                : URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
            rows.append(.folder(id: id, title: title.isEmpty ? path : title, depth: depth, isExpanded: isExpanded))
            guard isExpanded else { return }

            for childPath in (children[path] ?? []).sorted(by: localizedPathOrder) {
                appendFolder(childPath, depth: depth + 1, into: &rows)
            }
            for file in (directFiles[path] ?? []).sorted(by: fileOrder) {
                rows.append(.file(file, depth: depth + 1))
            }
        }

        var rows: [Row] = []
        appendFolder(rootPath, depth: 0, into: &rows)
        return rows
    }

    private static func localizedPathOrder(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs, isDirectory: true).lastPathComponent
            .localizedCaseInsensitiveCompare(URL(fileURLWithPath: rhs, isDirectory: true).lastPathComponent) == .orderedAscending
    }

    private static func fileOrder(_ lhs: DatabaseFileItem, _ rhs: DatabaseFileItem) -> Bool {
        lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
    }

    private static func filename(in path: String) -> String {
        guard let separator = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: separator)...])
    }
}
