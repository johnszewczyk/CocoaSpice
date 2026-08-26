import Foundation
import LocalFileBrowserCore
import Observation

@MainActor @Observable
final class LocalBrowserCoordinator {
    private(set) var rows: [LocalBrowserSidebarRow] = []
    private(set) var selectedPath: String?
    private var session: LocalFileBrowserSession?
    private var children: [String: [LocalFileBrowserNode]] = [:]
    private var expandedPaths: Set<String> = []

    var hasExpandedDescendantFolders: Bool {
        guard let rootPath = session?.rootURL.path else { return false }
        return expandedPaths.contains { $0 != rootPath }
    }

    var canToggleAllFolders: Bool {
        session != nil && !children.isEmpty
    }

    func configure(path: String, isPlayableFile: @escaping @Sendable (URL) -> Bool) throws -> LocalFileBrowserNode {
        let session = try LocalFileBrowserSession(
            rootURL: URL(fileURLWithPath: path, isDirectory: true),
            isPlayableFile: isPlayableFile
        )
        let root = try session.rootNode()
        self.session = session
        children = [root.path: root.children]
        expandedPaths = [root.path]
        selectedPath = root.path
        rebuildRows(root: root)
        return root
    }

    func clear() {
        session = nil
        children = [:]
        expandedPaths = []
        selectedPath = nil
        rows = []
    }

    func select(path: String) { selectedPath = path }

    func toggleFolder(path: String) throws {
        guard let session else { return }
        if expandedPaths.remove(path) != nil {
            rebuildRows()
            return
        }
        if children[path] == nil {
            children[path] = try session.children(of: URL(fileURLWithPath: path, isDirectory: true))
        }
        expandedPaths.insert(path)
        rebuildRows()
    }

    func setAllFoldersCollapsed(_ collapsed: Bool) {
        guard let rootPath = session?.rootURL.path else { return }
        expandedPaths = collapsed ? [rootPath] : Set(children.keys).union([rootPath])
        rebuildRows()
    }

    func resolve(path: String) throws -> URL? { try session?.resolve(path: path) }

    private func rebuildRows(root: LocalFileBrowserNode? = nil) {
        let rootNode: LocalFileBrowserNode
        if let root {
            rootNode = root
        } else if let path = session?.rootURL.path {
            rootNode = LocalFileBrowserNode(
                id: path,
                kind: .folder,
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                children: children[path] ?? [],
                childrenLoaded: true,
                alwaysExpanded: true
            )
        } else {
            rows = []
            return
        }
        var nextRows: [LocalBrowserSidebarRow] = []
        func append(_ node: LocalFileBrowserNode, depth: Int) {
            let expanded = node.alwaysExpanded || expandedPaths.contains(node.path)
            nextRows.append(LocalBrowserSidebarRow(node: node, depth: depth, isExpanded: expanded))
            guard node.kind == .folder, expanded else { return }
            for child in children[node.path] ?? node.children { append(child, depth: depth + 1) }
        }
        append(rootNode, depth: 0)
        rows = nextRows
    }
}
