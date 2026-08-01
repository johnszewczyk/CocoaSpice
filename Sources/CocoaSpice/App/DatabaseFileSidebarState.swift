import Foundation
import Observation

@MainActor
@Observable
final class DatabaseFileSidebarState {
    var searchText = "" {
        didSet {
            refreshVisibleItems()
        }
    }
    private(set) var fileItems: [DatabaseFileItem] = []
    private(set) var visibleFileItems: [DatabaseFileItem] = []
    private(set) var contentRevision = 0
    var selectedFileID: String?
    var selectedFileIDs: Set<String> = []
    var selectedFolders: Set<DatabaseFileSidebarFolder> = []
    var expandedFolderIDs: Set<String> = []

    func replaceFileItems(_ items: [DatabaseFileItem]) {
        fileItems = items
        expandedFolderIDs.formIntersection(Set(DatabaseFileSidebarTree.rootFolderIDs(for: items)))
        if let selectedFileID,
           !items.contains(where: { $0.id == selectedFileID }) {
            clearSelection()
        }
        refreshVisibleItems()
    }

    func clear() {
        fileItems = []
        visibleFileItems = []
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

    private func refreshVisibleItems() {
        visibleFileItems = DatabaseFileSidebarTree.filter(fileItems, query: searchText)
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
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            let haystack = "\(item.filename) \(item.folderPath) \(item.path)".lowercased()
            return terms.allSatisfy(haystack.contains)
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
}
