import Foundation
import Observation
import CatalogSessionCore

/// Owns database-sidebar cache lifetime and background snapshot reads. It does
/// not interpret selection, search, playback, or scan policy; those belong to
/// the view model that uses the published sidebar states.
@MainActor
@Observable
final class DatabaseSidebarLoader {
    private let gameSidebar: DatabaseSidebarState
    private let fileSidebar: DatabaseFileSidebarState
    private let catalogSessions = CatalogSessionCoordinator()
    private(set) var hasLoadedGames = false
    private(set) var hasLoadedFiles = false
    private(set) var gameLoadingStatus = ""
    private(set) var fileLoadingStatus = ""
    private(set) var gameLoadError: String?
    private(set) var fileLoadError: String?
    private(set) var isLoadingGames = false
    private(set) var isLoadingFiles = false

    init(gameSidebar: DatabaseSidebarState, fileSidebar: DatabaseFileSidebarState) {
        self.gameSidebar = gameSidebar
        self.fileSidebar = fileSidebar
    }

    func invalidateAndLoad(
        databaseURL: URL?,
        mode: SidebarBrowserMode,
        preferFoldersOverMetadata: Bool = true,
        didLoadGames: @escaping @MainActor () -> Void,
        didLoadFiles: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        catalogSessions.cancel(.games)
        catalogSessions.cancel(.files)
        hasLoadedGames = false
        hasLoadedFiles = false
        isLoadingGames = false
        isLoadingFiles = false
        gameLoadingStatus = ""
        fileLoadingStatus = ""
        gameLoadError = nil
        fileLoadError = nil
        if databaseURL == nil {
            gameSidebar.clear()
            fileSidebar.clear()
        }
        loadIfNeeded(
            databaseURL: databaseURL,
            mode: mode,
            preferFoldersOverMetadata: preferFoldersOverMetadata,
            didLoadGames: didLoadGames,
            didLoadFiles: didLoadFiles,
            didFail: didFail
        )
    }

    func loadIfNeeded(
        databaseURL: URL?,
        mode: SidebarBrowserMode,
        preferFoldersOverMetadata: Bool = true,
        didLoadGames: @escaping @MainActor () -> Void,
        didLoadFiles: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        guard let databaseURL else { return }
        switch mode {
        case .games:
            loadGamesIfNeeded(
                databaseURL: databaseURL,
                preferFoldersOverMetadata: preferFoldersOverMetadata,
                didLoad: didLoadGames,
                didFail: didFail
            )
        case .files:
            loadFilesIfNeeded(databaseURL: databaseURL, didLoad: didLoadFiles, didFail: didFail)
        case .localFiles:
            return
        }
    }

    func clear() {
        catalogSessions.cancel(.games)
        catalogSessions.cancel(.files)
        hasLoadedGames = false
        hasLoadedFiles = false
        isLoadingGames = false
        isLoadingFiles = false
        gameSidebar.clear()
        fileSidebar.clear()
        gameLoadingStatus = ""
        fileLoadingStatus = ""
        gameLoadError = nil
        fileLoadError = nil
    }

    private func loadGamesIfNeeded(
        databaseURL: URL,
        preferFoldersOverMetadata: Bool,
        didLoad: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor (String) -> Void
    ) {
        guard !hasLoadedGames, !isLoadingGames else { return }
        let generation = catalogSessions.begin(.games)
        isLoadingGames = true
        gameLoadingStatus = "Reading indexed games…"
        gameLoadError = nil
        let task = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> Result<[DatabaseGameItem], Error> in
                Result {
                    try CatalogBrowser.gameItems(
                        databaseURL: databaseURL,
                        preferFoldersOverMetadata: preferFoldersOverMetadata
                    )
                }
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.catalogSessions.isCurrent(generation, for: .games) else { return }
            self.gameLoadingStatus = ""
            self.catalogSessions.finish(generation, for: .games)
            self.isLoadingGames = false
            switch result {
            case .success(let items):
                self.gameSidebar.replaceGameItems(items)
                self.hasLoadedGames = true
                didLoad()
            case .failure(let error):
                let message = "Could not read the indexed games: \(error.localizedDescription)"
                self.gameLoadError = message
                didFail(message)
            }
        }
        catalogSessions.install(task, generation: generation, for: .games)
    }

    private func loadFilesIfNeeded(
        databaseURL: URL,
        didLoad: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor (String) -> Void
    ) {
        guard !hasLoadedFiles, !isLoadingFiles else { return }
        let generation = catalogSessions.begin(.files)
        isLoadingFiles = true
        fileLoadingStatus = "Reading scanned source records…"
        fileLoadError = nil
        let task = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> Result<[DatabaseFileItem], Error> in
                Result { try CatalogBrowser.fileItems(databaseURL: databaseURL) }
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.catalogSessions.isCurrent(generation, for: .files) else { return }
            guard case .success(let items) = result else {
                let message: String
                if case .failure(let error) = result {
                    message = "Could not read the scanned source records: \(error.localizedDescription)"
                } else {
                    preconditionFailure("Unexpected database sidebar load result")
                }
                self.fileLoadingStatus = ""
                self.catalogSessions.finish(generation, for: .files)
                self.isLoadingFiles = false
                self.fileLoadError = message
                didFail(message)
                return
            }
            self.fileLoadingStatus = "Building the folder tree…"
            let indexes = await Task.detached(priority: .utility) {
                (
                    DatabaseFileSidebarTree.Index(items: items),
                    DatabaseFileSidebarTree.SearchIndex(items: items)
                )
            }.value
            guard !Task.isCancelled,
                  self.catalogSessions.isCurrent(generation, for: .files) else { return }
            self.fileSidebar.replaceFileItems(
                items,
                treeIndex: indexes.0,
                searchIndex: indexes.1
            )
            self.hasLoadedFiles = true
            self.fileLoadingStatus = ""
            self.catalogSessions.finish(generation, for: .files)
            self.isLoadingFiles = false
            didLoad()
        }
        catalogSessions.install(task, generation: generation, for: .files)
    }
}
