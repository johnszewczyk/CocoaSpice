import Foundation
import Observation

/// Owns database-sidebar cache lifetime and background snapshot reads. It does
/// not interpret selection, search, playback, or scan policy; those belong to
/// the view model that uses the published sidebar states.
@MainActor
@Observable
final class DatabaseSidebarLoader {
    private let gameSidebar: DatabaseSidebarState
    private let fileSidebar: DatabaseFileSidebarState
    private let gameLoadTaskOwner = LatestTaskOwner()
    private let fileLoadTaskOwner = LatestTaskOwner()
    private(set) var hasLoadedGames = false
    private(set) var hasLoadedFiles = false
    private(set) var gameLoadingStatus = ""
    private(set) var fileLoadingStatus = ""
    private(set) var isLoadingGames = false
    private(set) var isLoadingFiles = false

    init(gameSidebar: DatabaseSidebarState, fileSidebar: DatabaseFileSidebarState) {
        self.gameSidebar = gameSidebar
        self.fileSidebar = fileSidebar
    }

    func invalidateAndLoad(
        databaseURL: URL?,
        mode: SidebarBrowserMode,
        didLoadGames: @escaping @MainActor () -> Void,
        didLoadFiles: @escaping @MainActor () -> Void
    ) {
        gameLoadTaskOwner.cancel()
        fileLoadTaskOwner.cancel()
        hasLoadedGames = false
        hasLoadedFiles = false
        isLoadingGames = false
        isLoadingFiles = false
        gameSidebar.clear()
        fileSidebar.clear()
        gameLoadingStatus = ""
        fileLoadingStatus = ""
        loadIfNeeded(
            databaseURL: databaseURL,
            mode: mode,
            didLoadGames: didLoadGames,
            didLoadFiles: didLoadFiles
        )
    }

    func loadIfNeeded(
        databaseURL: URL?,
        mode: SidebarBrowserMode,
        didLoadGames: @escaping @MainActor () -> Void,
        didLoadFiles: @escaping @MainActor () -> Void
    ) {
        guard let databaseURL else { return }
        switch mode {
        case .games:
            loadGamesIfNeeded(databaseURL: databaseURL, didLoad: didLoadGames)
        case .files:
            loadFilesIfNeeded(databaseURL: databaseURL, didLoad: didLoadFiles)
        }
    }

    func clear() {
        gameLoadTaskOwner.cancel()
        fileLoadTaskOwner.cancel()
        hasLoadedGames = false
        hasLoadedFiles = false
        isLoadingGames = false
        isLoadingFiles = false
        gameSidebar.clear()
        fileSidebar.clear()
        gameLoadingStatus = ""
        fileLoadingStatus = ""
    }

    private func loadGamesIfNeeded(databaseURL: URL, didLoad: @escaping @MainActor () -> Void) {
        guard !hasLoadedGames, !isLoadingGames else { return }
        let generation = gameLoadTaskOwner.begin()
        isLoadingGames = true
        gameLoadingStatus = "Reading indexed games…"
        let task = Task { [weak self] in
            let items = await Task.detached(priority: .utility) {
                (try? LibraryDatabase.loadGameSidebarItems(databaseURL: databaseURL)) ?? []
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.gameLoadTaskOwner.isCurrent(generation) else { return }
            self.gameSidebar.replaceGameItems(items)
            self.hasLoadedGames = true
            self.gameLoadingStatus = ""
            self.gameLoadTaskOwner.finish(generation: generation)
            self.isLoadingGames = false
            didLoad()
        }
        gameLoadTaskOwner.install(task, generation: generation)
    }

    private func loadFilesIfNeeded(databaseURL: URL, didLoad: @escaping @MainActor () -> Void) {
        guard !hasLoadedFiles, !isLoadingFiles else { return }
        let generation = fileLoadTaskOwner.begin()
        isLoadingFiles = true
        fileLoadingStatus = "Reading scanned source records…"
        let task = Task { [weak self] in
            let items = await Task.detached(priority: .utility) {
                (try? LibraryDatabase.loadFileSidebarItems(databaseURL: databaseURL)) ?? []
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.fileLoadTaskOwner.isCurrent(generation) else { return }
            self.fileLoadingStatus = "Building the folder tree…"
            let indexes = await Task.detached(priority: .utility) {
                (
                    DatabaseFileSidebarTree.Index(items: items),
                    DatabaseFileSidebarTree.SearchIndex(items: items)
                )
            }.value
            guard !Task.isCancelled,
                  self.fileLoadTaskOwner.isCurrent(generation) else { return }
            self.fileSidebar.replaceFileItems(
                items,
                treeIndex: indexes.0,
                searchIndex: indexes.1
            )
            self.hasLoadedFiles = true
            self.fileLoadingStatus = ""
            self.fileLoadTaskOwner.finish(generation: generation)
            self.isLoadingFiles = false
            didLoad()
        }
        fileLoadTaskOwner.install(task, generation: generation)
    }
}
