import Foundation

/// Owns database-sidebar cache lifetime and background snapshot reads. It does
/// not interpret selection, search, playback, or scan policy; those belong to
/// the view model that uses the published sidebar states.
@MainActor
final class DatabaseSidebarLoader {
    private let gameSidebar: DatabaseSidebarState
    private let fileSidebar: DatabaseFileSidebarState
    private let gameLoadTaskOwner = LatestTaskOwner()
    private let fileLoadTaskOwner = LatestTaskOwner()
    private(set) var hasLoadedGames = false
    private(set) var hasLoadedFiles = false

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
        isLoadingGames = false
        isLoadingFiles = false
        hasLoadedGames = false
        hasLoadedFiles = false
        gameSidebar.clear()
        fileSidebar.clear()
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
        isLoadingGames = false
        isLoadingFiles = false
        hasLoadedGames = false
        hasLoadedFiles = false
        gameSidebar.clear()
        fileSidebar.clear()
    }

    private func loadGamesIfNeeded(databaseURL: URL, didLoad: @escaping @MainActor () -> Void) {
        guard !hasLoadedGames, !isLoadingGames else { return }
        let generation = gameLoadTaskOwner.begin()
        isLoadingGames = true
        let task = Task { [weak self] in
            let items = await Task.detached(priority: .utility) {
                (try? LibraryDatabase.loadGameSidebarItems(databaseURL: databaseURL)) ?? []
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.gameLoadTaskOwner.isCurrent(generation) else { return }
            self.gameSidebar.replaceGameItems(items)
            self.hasLoadedGames = true
            self.isLoadingGames = false
            didLoad()
            self.gameLoadTaskOwner.finish(generation: generation)
        }
        gameLoadTaskOwner.install(task, generation: generation)
    }

    private func loadFilesIfNeeded(databaseURL: URL, didLoad: @escaping @MainActor () -> Void) {
        guard !hasLoadedFiles, !isLoadingFiles else { return }
        let generation = fileLoadTaskOwner.begin()
        isLoadingFiles = true
        let task = Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) {
                let items = (try? LibraryDatabase.loadFileSidebarItems(databaseURL: databaseURL)) ?? []
                return (
                    items,
                    DatabaseFileSidebarTree.Index(items: items),
                    DatabaseFileSidebarTree.SearchIndex(items: items)
                )
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.fileLoadTaskOwner.isCurrent(generation) else { return }
            self.fileSidebar.replaceFileItems(
                loaded.0,
                treeIndex: loaded.1,
                searchIndex: loaded.2
            )
            self.hasLoadedFiles = true
            self.isLoadingFiles = false
            didLoad()
            self.fileLoadTaskOwner.finish(generation: generation)
        }
        fileLoadTaskOwner.install(task, generation: generation)
    }
}
