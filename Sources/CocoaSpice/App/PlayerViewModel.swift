import AppKit
import ArchiveCacheCore
import FrontendPreferencesCore
import CatalogBrowserCore
import CatalogReader
import CatalogSessionCore
import Foundation
import FavoriteStoreCore
import FavoriteTrackCore
import OSLog
import Observation
import LocalFileBrowserCore
import PlaybackQueueCore
import PlaybackTransportCore
import UniformTypeIdentifiers
import VGMBoyKit

enum SidebarBrowserMode: String, CaseIterable, Identifiable {
    case games
    case files
    case localFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .games: "Console View"
        case .files: "Path View"
        case .localFiles: "Local Files"
        }
    }

    var iconName: String {
        switch self {
        case .games: "square.grid.2x2"
        case .files: "folder"
        case .localFiles: "externaldrive"
        }
    }
}

struct LocalBrowserSidebarRow: Identifiable, Equatable, Sendable {
    let node: LocalFileBrowserNode
    let depth: Int
    let isExpanded: Bool

    var id: String { node.id }
}

enum SidebarPresentationView: String, Sendable {
    case folders
    case database
    case search
}

struct SidebarViewResolution: Equatable, Sendable {
    let storedMode: SidebarPresentationView
    let query: String
    let view: SidebarPresentationView
    let contentMode: SidebarPresentationView
    let resultSource: String
    let isTemporary: Bool
}

@MainActor
@Observable
final class PlayerViewModel {
    private static let playlistLoadLogger = Logger(
        subsystem: "com.local.cocoaspice",
        category: "playlist-load"
    )
    enum RepeatMode: String, CaseIterable, Identifiable {
        case off, playlist, song
        var id: Self { self }
        var title: String {
            switch self { case .off: "Repeat Off"; case .playlist: "Repeat Playlist"; case .song: "Repeat Song" }
        }
        var iconName: String { self == .song ? "repeat.1" : "repeat" }
    }
    enum RandomPlaybackScope: String, CaseIterable, Identifiable {
        case off, library, playlist
        var id: Self { self }
        var title: String {
            switch self { case .off: "Random Off"; case .library: "Random Library"; case .playlist: "Random Playlist" }
        }
        var iconName: String {
            switch self { case .off: "shuffle"; case .library: "books.vertical.fill"; case .playlist: "music.note.list" }
        }
    }
    enum SidebarDoubleClickAction: String, CaseIterable, Identifiable {
        case playNow
        case enqueue

        var id: String { rawValue }

        var title: String {
            switch self {
            case .playNow: "Set as Playlist"
            case .enqueue: "Add to Playlist"
            }
        }
    }

    enum DatabaseSidebarTextColor: String, CaseIterable, Identifiable {
        case primary
        case secondary
        case tertiary

        var id: String { rawValue }

        var title: String {
            switch self {
            case .secondary: "Secondary"
            case .primary: "Primary"
            case .tertiary: "Tertiary"
            }
        }
    }

    enum PlaylistSortColumn: String, CaseIterable, Identifiable {
        case index
        case file
        case title
        case game
        case author
        case system
        case path
        case length

        var id: String { rawValue }

        var title: String {
            switch self {
            case .index: "#"
            case .file: "File"
            case .title: "Title"
            case .game: "Game"
            case .author: "Author"
            case .system: "System"
            case .path: "Path"
            case .length: "Length"
            }
        }
    }

    enum PlaylistSortDirection: String, Sendable {
        case ascending
        case descending

        mutating func toggle() {
            self = self == .ascending ? .descending : .ascending
        }
    }

    var catalogRoots: [CatalogRoot] = []
    var sidebarDoubleClickAction: SidebarDoubleClickAction = .playNow
    var rootURL: URL?
    var selectedFolderPath: String?
    var librarySelectedFolderPath: String?
    let databaseSidebar = DatabaseSidebarState()
    let databaseFileSidebar = DatabaseFileSidebarState()
    private var sidebarSearchPersistenceWorkItem: DispatchWorkItem?
    private var sidebarSearchQuery = ""
    var sidebarSearchText: String {
        get { sidebarSearchQuery }
        set {
            guard sidebarSearchQuery != newValue else { return }
            sidebarSearchQuery = newValue
            applySidebarSearch()
            scheduleSidebarSearchPersistence()
        }
    }
    var interfaceFontSize: CGFloat = 12
    var interfaceTextColor: DatabaseSidebarTextColor = .primary
    var interfaceMonospaceFont = false
    let frontendPreferences = FrontendPreferencesCoordinator(keys: .cocoaSpice)
    var autoResizeAnimationEnabled: Bool { frontendPreferences.value.animations.autoResizeEnabled }
    var selectionAnimationEnabled: Bool { frontendPreferences.value.animations.selectionEnabled }
    var autoResizeAnimationMilliseconds: Int { frontendPreferences.value.animations.autoResizeMilliseconds }
    var effectiveAutoResizeAnimationMilliseconds: Int {
        autoResizeAnimationEnabled ? frontendPreferences.value.animations.autoResizeMilliseconds : 0
    }
    var selectionAnimationMilliseconds: Int { frontendPreferences.value.animations.selectionMilliseconds }
    var effectiveSelectionAnimationMilliseconds: Int {
        selectionAnimationEnabled ? frontendPreferences.value.animations.selectionMilliseconds : 0
    }
    var columnAutoSizeEnabled: Bool { frontendPreferences.value.columnAutoSize }
    var mainWindowAlwaysOnTop: Bool { frontendPreferences.value.windows.mainAlwaysOnTop }
    var settingsWindowAlwaysOnTop: Bool { frontendPreferences.value.windows.settingsAlwaysOnTop }
    var databaseSidebarFontSize: CGFloat {
        get { interfaceFontSize }
        set { interfaceFontSize = newValue }
    }
    var databaseSidebarTextColor: DatabaseSidebarTextColor {
        get { interfaceTextColor }
        set { interfaceTextColor = newValue }
    }
    var databaseSidebarMonospaceFont: Bool {
        get { interfaceMonospaceFont }
        set { interfaceMonospaceFont = newValue }
    }
    /// Space between a Files-mode disclosure triangle and its label, in points.
    var databaseSidebarDisclosureGapPoints: CGFloat = 6
    /// Extra hierarchy offset applied for each Files-mode child depth, in points.
    var databaseSidebarChildIndentPoints: CGFloat = 8
    var databaseSidebarHidesFileExtensions = false
    var playlistFontSize: CGFloat {
        get { interfaceFontSize }
        set { interfaceFontSize = newValue }
    }
    var playlistTextColor: DatabaseSidebarTextColor {
        get { interfaceTextColor }
        set { interfaceTextColor = newValue }
    }
    var playlistMonospaceFont: Bool {
        get { interfaceMonospaceFont }
        set { interfaceMonospaceFont = newValue }
    }
    var sidebarBrowserMode: SidebarBrowserMode = .games
    var effectiveSidebarBrowserMode: SidebarBrowserMode {
        Self.effectiveSidebarBrowserMode(storedMode: sidebarBrowserMode, searchText: sidebarSearchQuery)
    }
    var effectiveSidebarPresentationView: SidebarPresentationView {
        Self.sidebarViewResolution(storedMode: sidebarBrowserMode, searchText: sidebarSearchQuery).view
    }
    var sidebarSystemMode = false
    var preferEmbeddedConsoleTags = false

    nonisolated static func effectiveSidebarBrowserMode(
        storedMode: SidebarBrowserMode,
        searchText: String
    ) -> SidebarBrowserMode {
        if storedMode == .localFiles { return .localFiles }
        return sidebarViewResolution(storedMode: storedMode, searchText: searchText).contentMode == .folders
            ? SidebarBrowserMode.files
            : SidebarBrowserMode.games
    }

    nonisolated static func sidebarViewResolution(
        storedMode: SidebarBrowserMode,
        searchText: String
    ) -> SidebarViewResolution {
        let sharedMode: CatalogBrowserMode = switch storedMode {
        case .files: .paths
        case .localFiles: .diskPath
        case .games: .consoles
        }
        let shared = CatalogBrowserState(mode: sharedMode, query: searchText)
        let presentation: (CatalogBrowserView) -> SidebarPresentationView = { view in
            switch view {
            case .paths, .diskPath: .folders
            case .consoles: .database
            case .search: .search
            }
        }
        let content: SidebarPresentationView = switch shared.contentMode {
        case .tree: .folders
        case .database: .database
        }
        let storedPresentation: SidebarPresentationView = switch shared.storedMode {
        case .paths, .diskPath: .folders
        case .consoles: .database
        }
        return SidebarViewResolution(
            storedMode: storedPresentation,
            query: shared.query,
            view: presentation(shared.view),
            contentMode: content,
            resultSource: content == .folders ? "folder-tree" : "database-index",
            isTemporary: shared.view == .search
        )
    }
    private(set) var expandedDatabaseSystems: Set<String> = []
    private var databaseGroupState = CatalogBrowserGroupState()
    var databaseGameItems: [DatabaseGameItem] { databaseSidebar.gameItems }
    var visibleDatabaseGameItems: [DatabaseGameItem] { databaseSidebar.visibleGameItems }
    var databaseFileItems: [DatabaseFileItem] { databaseFileSidebar.fileItems }
    var visibleDatabaseFileItems: [DatabaseFileItem] { databaseFileSidebar.visibleFileItems }
    var selectedDatabaseFileID: String? {
        get { databaseFileSidebar.selectedFileID }
        set { databaseFileSidebar.selectedFileID = newValue }
    }
    var selectedDatabaseFileIDs: Set<String> {
        get { databaseFileSidebar.selectedFileIDs }
        set { databaseFileSidebar.selectedFileIDs = newValue }
    }
    var selectedDatabaseFileFolders: Set<DatabaseFileSidebarFolder> {
        get { databaseFileSidebar.selectedFolders }
        set { databaseFileSidebar.selectedFolders = newValue }
    }
    var selectedDatabaseGameID: String? {
        get { databaseSidebar.selectedGameID }
        set { databaseSidebar.selectedGameID = newValue }
    }
    var selectedDatabaseGameIDs: Set<String> {
        get { databaseSidebar.selectedGameIDs }
        set { databaseSidebar.selectedGameIDs = newValue }
    }
    var browsedFolderTracks: [TrackItem] = []
    let queue = PlaylistQueueCoordinator()
    var selectedTrackID: TrackItem.ID? {
        get { queue.primarySelection }
        set { queue.primarySelection = newValue }
    }
    var selectedTrackIDs: Set<TrackItem.ID> {
        get { queue.selection }
        set { queue.selection = newValue }
    }
    var playlist: [TrackItem] {
        get { queue.tracks }
        set {
            queue.replaceTracks(with: newValue)
            if !isRestoringPersistedPlaylist {
                deferredPersistedPlaylistValues = []
            }
            refreshPlaylistTotalDurationReadout()
        }
    }
    let favorites = FavoritesCoordinator()
    var favoriteRecords: [FavoriteTrackSnapshot] { favorites.records }
    var favoriteRevision: Int { favorites.presentationRevision }
    var favoriteSortOrder: FavoriteSortOrder = .historical
    var displayedFavoriteRecords: [FavoriteTrackSnapshot] {
        FavoriteListPresentation.ordered(favoriteRecords, by: favoriteSortOrder)
    }
    var favoriteTracks: [TrackItem] {
        displayedFavoriteRecords.map { snapshot in
            if let entry = snapshot.identity.archiveEntry {
                return TrackItem(
                    archiveURL: URL(fileURLWithPath: snapshot.identity.sourcePath),
                    entryPath: entry,
                    trackIndex: snapshot.identity.trackIndex,
                    trackCount: snapshot.identity.trackCount
                )
            }
            return TrackItem(
                url: URL(fileURLWithPath: snapshot.identity.sourcePath),
                trackIndex: snapshot.identity.trackIndex,
                trackCount: snapshot.identity.trackCount
            )
        }
    }
    var localBrowserEnabled = false
    var localBrowserPath = ""
    let localBrowser = LocalBrowserCoordinator()
    var localBrowserRows: [LocalBrowserSidebarRow] { localBrowser.rows }
    var selectedLocalBrowserPath: String? { localBrowser.selectedPath }

    var sidebarDisclosureControlEnabled: Bool {
        switch effectiveSidebarBrowserMode {
        case .games:
            sidebarSystemMode && !databaseGameItems.isEmpty
        case .files:
            !databaseFileSidebar.allFolderIDs.isEmpty
        case .localFiles:
            localBrowser.canToggleAllFolders
        }
    }

    var sidebarDisclosureControlTitle: String {
        sidebarHasExpandedItems ? "Fold All" : "Unfold All"
    }

    var sidebarDisclosureControlIconName: String {
        sidebarHasExpandedItems ? "chevron.up.square" : "chevron.down.square"
    }

    func toggleSidebarDisclosureAll() {
        guard sidebarDisclosureControlEnabled else { return }
        let shouldCollapse = sidebarHasExpandedItems
        switch effectiveSidebarBrowserMode {
        case .games:
            let knownGroups = Set(databaseGameItems.map(sidebarSystemName(for:)))
            applyDatabaseGroupState(.setAllCollapsed(shouldCollapse, knownGroupNames: knownGroups))
        case .files:
            databaseFileSidebar.setAllFoldersCollapsed(shouldCollapse)
        case .localFiles:
            localBrowser.setAllFoldersCollapsed(shouldCollapse)
        }
    }

    private var sidebarHasExpandedItems: Bool {
        switch effectiveSidebarBrowserMode {
        case .games:
            !expandedDatabaseSystems.isEmpty
        case .files:
            !databaseFileSidebar.expandedFolderIDs.isEmpty
        case .localFiles:
            localBrowser.hasExpandedDescendantFolders
        }
    }
    var playlistContentRevision: Int { queue.contentRevision }
    private var isRestoringPersistedPlaylist = false
    private var deferredPersistedPlaylistValues: [String] = []
    var metadataCache: [String: TrackMetadata] = [:]
    private(set) var playlistTotalDurationReadout = "0:00"
    private var playlistDurationSecondsByTrackID: [TrackItem.ID: Int] = [:]
    private var playlistDurationTrackIDs: Set<TrackItem.ID> = []
    private var playlistDurationTotalSeconds = 0
    var playlistColumnWidthHints: PlaylistColumnWidthHints?
    var playlistSortColumn: PlaylistSortColumn?
    var playlistSortDirection: PlaylistSortDirection = .ascending
    var currentTrack: TrackItem?
    var currentMetadata: TrackMetadata?
    var equalizerEnabled = false {
        didSet { playbackStorage?.setEqualizer(enabled: equalizerEnabled, bandGains: equalizerBandGains) }
    }
    var equalizerBandGains = AudioEqualizer.bandFrequencies.map { _ in Float.zero }
    var appVolume: Float = 1 {
        didSet { playbackStorage?.setAppVolume(appVolume) }
    }
    var monoEnabled = false {
        didSet { playbackStorage?.setMonoEnabled(monoEnabled) }
    }
    var randomPlaybackScope: RandomPlaybackScope = .off
    var repeatMode: RepeatMode = .off
    private var randomLibraryTracks: [TrackItem] = []
    var playlistFollowsCursor = false
    var longPlayEnabled = false
    var manualPreFadeSeconds: Int = 180
    var unknownDurationSeconds: Int = PlaybackTimingPreferences.defaultUnknownDurationSeconds
    var endFadeEnabled = true
    var configuredFadeSeconds: Int = PlaybackTimingPreferences.defaultFadeSeconds
    var fadedSkipEnabled = false
    var libgmeTempo = PlaybackTempo.defaultValue
    var libgmeTempoEnabled = false
    var libvgmTempo = PlaybackTempo.defaultValue
    var libvgmTempoEnabled = false
    var fadeSeconds: Int { endFadeEnabled ? configuredFadeSeconds : 0 }
    private var fadedSkipTask: Task<Void, Never>?
    private var fadedSkipToken: UUID?
    var statusText: String = "Choose a music folder to begin."
    var isLoading = false
    var isPlaying = false
    var playbackElapsedSeconds: TimeInterval = 0
    private(set) var playbackDiagnostics = PlaybackDiagnosticsSnapshot.idle
    var isSeeking = false
    var seekPreviewSeconds: Double = 0
    var playlistMetadataLoadToken = 0
    private(set) var playlistMetadataChangedTrackIDs: Set<TrackItem.ID> = []
    var libraryDatabaseLocationStatus: String?
    private(set) var archiveCacheSummaryText = "Unavailable"
    private(set) var isClearingArchiveCache = false
    var archiveCachePolicy = ArchiveCachePolicy.load()
    var isExportingAAC = false
    private var selectedAACExportDirectory: URL?
    private(set) var deadLinkSummaryText = "Unavailable"
    private(set) var deadLinkCount = 0
    private(set) var databaseEntryCount = 0
    private(set) var unlinkedDatabaseEntryCount = 0
    private(set) var isDeletingDeadLinks = false
    var isLoadingDatabaseSidebar: Bool { databaseSidebarLoader.isLoadingGames }
    var isLoadingDatabaseFileSidebar: Bool { databaseSidebarLoader.isLoadingFiles }
    var databaseSidebarLoadingStatus: String {
        switch effectiveSidebarBrowserMode {
        case .games:
            databaseSidebarLoader.gameLoadingStatus.isEmpty
                ? "Reading indexed games…"
                : databaseSidebarLoader.gameLoadingStatus
        case .files:
            databaseSidebarLoader.fileLoadingStatus.isEmpty
                ? "Preparing the folder tree…"
                : databaseSidebarLoader.fileLoadingStatus
        case .localFiles:
            "Reading Local Files"
        }
    }
    var databaseSidebarLoadError: String? {
        switch effectiveSidebarBrowserMode {
        case .games: databaseSidebarLoader.gameLoadError
        case .files: databaseSidebarLoader.fileLoadError
        case .localFiles: nil
        }
    }

    func retryDatabaseSidebarLoad() {
        loadDatabaseSidebarIfNeeded()
    }

    /// Reloads the externally published catalog snapshot. Playback keeps its
    /// loaded queue; only the Database browser is refreshed.
    func reloadLibrary() {
        guard !localBrowserEnabled else {
            libraryDatabaseLocationStatus = "Turn off Local Files before reloading the database library."
            return
        }
        guard libraryDatabase != nil else {
            libraryDatabaseLocationStatus = "Library database is unavailable."
            return
        }
        reloadCatalogRoots()
        databaseSidebar.clearSelection()
        databaseFileSidebar.clearSelection()
        selectedDatabaseGameIDs.removeAll()
        selectedDatabaseFileIDs.removeAll()
        selectedDatabaseFileFolders.removeAll()
        reloadDatabaseSidebar()
        libraryDatabaseLocationStatus = "Reloading the current MediaScanner catalog…"
    }

    var enabledCatalogRootURLs: [URL] {
        catalogRoots
            .filter(\.isEnabled)
            .map(\.standardizedURL)
    }

    var libraryDatabaseURL: URL? {
        libraryDatabase?.databaseURL
    }

    var libraryDatabaseIsReadOnly: Bool {
        libraryDatabase?.isReadOnly ?? true
    }

    var configuredLibraryDatabasePath: String {
        (try? LibraryDatabase.configuredDatabaseURL().path) ?? "Library database unavailable"
    }

    /// The frontend persists only its output-folder preference. VGMBoy is
    /// passed that folder and owns validation, safe naming, collisions, and
    /// AAC generation; no catalog metadata crosses the boundary.
    var aacExportDirectory: URL {
        if let selectedAACExportDirectory { return selectedAACExportDirectory }
        if let stored = UserDefaults.standard.string(forKey: AppDefaultsKey.aacExportDirectory), !stored.isEmpty {
            return URL(fileURLWithPath: stored, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
    }

    var aacExportDirectoryPath: String { aacExportDirectory.path }

    func chooseAACExportDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose AAC Export Folder"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = aacExportDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setAACExportDirectory(url)
    }

    func setAACExportDirectory(_ url: URL) {
        let directory = url.standardizedFileURL
        selectedAACExportDirectory = directory
        UserDefaults.standard.set(directory.path, forKey: AppDefaultsKey.aacExportDirectory)
    }

    func exportTrackAsAAC(_ track: TrackItem) {
        guard !isExportingAAC else {
            statusText = "AAC export already in progress"
            return
        }
        isExportingAAC = true
        let catalogMetadata = metadataCache[track.id]
        let plan = playbackPlan(for: catalogMetadata, trackPathExtension: track.playablePathExtension)
        let destination = aacExportDirectory
        statusText = "Exporting \(track.displayName) to AAC…"
        let playback = self.playback
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isExportingAAC = false }
            do {
                let output = try await playback.exportAAC(
                    track: track,
                    plan: plan,
                    outputDirectory: destination,
                    filenameStem: catalogMetadata?.song.nonEmpty ?? track.displayName
                )
                self.statusText = "Exported AAC: \(output.lastPathComponent)"
            } catch {
                self.statusText = error.localizedDescription
            }
        }
    }

    func chooseLibraryDatabase() {
        let panel = NSOpenPanel()
        panel.title = "Choose Library Database"
        panel.prompt = "Choose Database"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.database]
        if let current = try? LibraryDatabase.configuredDatabaseURL() {
            panel.directoryURL = current.deletingLastPathComponent()
            panel.nameFieldStringValue = current.lastPathComponent
        }
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        selectLibraryDatabase(at: selectedURL)
    }

    /// Validates a catalog selected by any presentation layer. The native
    /// Options window supplies this URL through `NSOpenPanel`; another skin
    /// supplies the same path through its control surface.
    func selectLibraryDatabase(at selectedURL: URL) {
        do {
            let summary = try ReadOnlyCatalog(databaseURL: selectedURL).summary()
            UserDefaults.standard.set(summary.path, forKey: AppDefaultsKey.libraryDatabasePath)
            libraryDatabaseLocationStatus = selectedURL.standardizedFileURL == libraryDatabaseURL?.standardizedFileURL
                ? "This database is already active. Use Reload Library after it has been republished."
                : "Validated \(summary.trackCount) tracks. Restart CocoaSpice to load a different catalog."
        } catch {
            libraryDatabaseLocationStatus = "Database not selected: \(error.localizedDescription)"
        }
    }

    func useDefaultLibraryDatabase() {
        UserDefaults.standard.removeObject(forKey: AppDefaultsKey.libraryDatabasePath)
        let defaultPath = (try? LibraryDatabase.defaultDatabaseURL().path) ?? "the default database"
        libraryDatabaseLocationStatus = libraryDatabaseURL?.path == defaultPath
            ? "The default database is already active."
            : "Restart CocoaSpice to use the default database."
    }

    @ObservationIgnored private var playbackStorage: PlaybackEngine?
    @ObservationIgnored private var remoteTransportStorage: RemoteTransportController?
    @ObservationIgnored private lazy var optionsControlSurfaceStorage = CocoaSpiceOptionsControlSurface(model: self)
    @ObservationIgnored private lazy var mainPlaybackControlSurfaceStorage = CocoaSpiceMainPlaybackControlSurface(model: self)
    private var remoteTransportConfigured = false
    private let libraryDatabase: LibraryDatabase?
    private var playbackTimer: Timer?
    private let playlistMetadataTaskOwner = LatestTaskOwner()
    private let playbackRequestState = PlaybackRequestState()
    private let folderSelectionTaskOwner = LatestTaskOwner()
    private let queueBuildTaskOwner = LatestTaskOwner()
    private let randomLibraryLoadTaskOwner = LatestTaskOwner()
    private var archiveCacheSummaryTask: Task<Void, Never>?
    private var archiveCacheClearTask: Task<Void, Never>?
    private let databaseFileSidebarSearchTaskOwner = LatestTaskOwner()
    private let libraryRootEnableTaskOwner = LatestTaskOwner()
    @ObservationIgnored private lazy var databaseSidebarLoader = DatabaseSidebarLoader(
        gameSidebar: databaseSidebar,
        fileSidebar: databaseFileSidebar
    )
    private var playlistMetadataRefreshWorkItem: DispatchWorkItem?
    private var randomLibraryPlaybackPending = false
    private var didAutoAdvanceForCurrentTrack: Bool {
        get { playbackRequestState.didAutoAdvance }
        set { playbackRequestState.didAutoAdvance = newValue }
    }
    private var playbackReachedEnd: Bool {
        get { playbackRequestState.reachedEnd }
        set { playbackRequestState.reachedEnd = newValue }
    }
    private var pendingPlaybackTrack: TrackItem? {
        get { playbackRequestState.pendingTrack }
        set { playbackRequestState.pendingTrack = newValue }
    }
    private var playlistClipboard: [TrackItem] = []
    private var playlistManualOrder: [String: Int] = [:]
    var pendingPlaylistColumnOrder: [String]?
    var pendingPlaylistColumnVisibility: [String: Bool]?
    var pendingPlaylistColumnWidths: [String: Double]?

    private var playback: PlaybackEngine {
        if let playbackStorage {
            return playbackStorage
        }
        let playback = PlaybackEngine()
        playback.setEqualizer(enabled: equalizerEnabled, bandGains: equalizerBandGains)
        playback.setAppVolume(appVolume)
        playback.setMonoEnabled(monoEnabled)
        playback.setPlaybackStateHandler { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isSeeking {
                    self.playbackElapsedSeconds = snapshot.elapsedSeconds
                }
                self.isPlaying = snapshot.isPlaying
                self.playbackReachedEnd = snapshot.reachedEnd
                self.updateRemoteTransportState()
            }
        }
        playback.setPlaybackNaturalEndHandler { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playbackReachedEnd = true
                if !self.isSeeking {
                    self.playbackElapsedSeconds = snapshot.elapsedSeconds
                }
                self.isPlaying = false
                self.handlePlaybackCompletionIfNeeded()
                self.updateRemoteTransportState()
            }
        }
        playbackStorage = playback
        return playback
    }

    /// Skin-neutral endpoint for the existing Options panels. The SwiftUI
    /// shell still binds directly to this model while a future WebKit shell
    /// can query a Codable snapshot and submit typed commands here.
    var optionsControlSurface: CocoaSpiceOptionsControlSurface {
        optionsControlSurfaceStorage
    }

    /// Skin-neutral endpoint for the transport and playback-policy controls
    /// in the main shell. Playlist/sidebar selection has a separate contract.
    var mainPlaybackControlSurface: CocoaSpiceMainPlaybackControlSurface {
        mainPlaybackControlSurfaceStorage
    }

    private var remoteTransport: RemoteTransportController {
        if let remoteTransportStorage {
            return remoteTransportStorage
        }
        let remoteTransport = RemoteTransportController()
        remoteTransportStorage = remoteTransport
        return remoteTransport
    }

    private var remoteNowPlaying: RemoteTransportNowPlaying {
        RemoteTransportNowPlaying(
            title: currentSongTitle,
            albumTitle: currentGameTitle,
            elapsedSeconds: playbackElapsedSeconds,
            durationSeconds: Double(totalPlaybackSeconds),
            isPlaying: isPlaying
        )
    }

    init() {
        let restoredState = AppSessionPersistence.restoreStartupState(
            supportedExtensions: PlaybackFormatRegistry.supportedExtensions
        )
        do {
            libraryDatabase = try LibraryDatabase()
        } catch {
            libraryDatabase = nil
            libraryDatabaseLocationStatus = "Library database unavailable: \(error.localizedDescription)"
        }
        restorePlaybackPreferences(restoredState.playbackPreferences)
        restoreLocalBrowserPreferences()
        restoreFavorites()
        Task { [weak self] in
            let recovery = await Task.detached(priority: .utility) {
                ZipArchiveSupport.reclaimAbandonedMaterializations()
            }.value
            guard recovery.rootCount > 0 else { return }
            self?.statusText = "Recovered \(recovery.rootCount) abandoned CocoaSpice cache items (\(ByteCountFormatter.string(fromByteCount: recovery.byteCount, countStyle: .file)))."
        }
        reloadCatalogRoots()
        if localBrowserEnabled {
            configureLocalBrowser(path: localBrowserPath)
        } else {
            reloadDatabaseSidebar()
        }
        restorePersistedPlaylist(restoredState.sessionState)
        restorePlaylistColumnState(restoredState.playlistColumnState)
        sidebarSearchText = restoredState.sidebarSearchText
        startPlaybackTimer()
        if !localBrowserEnabled {
            restoreInitialSidebarMode(
                lastRootPath: restoredState.lastRootPath,
                lastLibrarySelectedFolderPath: restoredState.lastLibrarySelectedFolderPath
            )
        }
        updateRemoteTransportState()
    }

    private func restoreLocalBrowserPreferences() {
        let defaults = UserDefaults.standard
        favoriteSortOrder = FavoriteSortOrder(
            rawValue: defaults.string(forKey: AppDefaultsKey.favoriteSortOrder) ?? "historical"
        ) ?? .historical
        localBrowserPath = defaults.string(forKey: AppDefaultsKey.localBrowserPath) ?? ""
        localBrowserEnabled = defaults.bool(forKey: AppDefaultsKey.localBrowserEnabled)
            && !localBrowserPath.isEmpty
        if localBrowserEnabled { sidebarBrowserMode = .localFiles }
    }

    func setAutoResizeAnimationMilliseconds(_ value: Int) {
        frontendPreferences.setAutoResizeMilliseconds(value)
    }

    func setAutoResizeAnimationEnabled(_ enabled: Bool) {
        frontendPreferences.setAutoResizeEnabled(enabled)
    }

    func setSelectionAnimationMilliseconds(_ value: Int) {
        frontendPreferences.setSelectionMilliseconds(value)
    }

    func setSelectionAnimationEnabled(_ enabled: Bool) {
        frontendPreferences.setSelectionEnabled(enabled)
    }

    func setColumnAutoSizeEnabled(_ enabled: Bool) {
        frontendPreferences.setColumnAutoSize(enabled)
    }

    func setMainWindowAlwaysOnTop(_ enabled: Bool) {
        frontendPreferences.setAlwaysOnTop(enabled, role: .main)
    }

    func setSettingsWindowAlwaysOnTop(_ enabled: Bool) {
        frontendPreferences.setAlwaysOnTop(enabled, role: .settings)
    }

    func setFavoriteSortOrder(_ order: FavoriteSortOrder) {
        guard favoriteSortOrder != order else { return }
        favoriteSortOrder = order
        UserDefaults.standard.set(order.rawValue, forKey: AppDefaultsKey.favoriteSortOrder)
        favorites.presentationChanged()
    }

    func setLocalBrowserEnabled(_ enabled: Bool) {
        if enabled && localBrowserPath.isEmpty {
            chooseLocalBrowserRoot()
            return
        }
        localBrowserEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppDefaultsKey.localBrowserEnabled)
        if enabled {
            sidebarBrowserMode = .localFiles
            configureLocalBrowser(path: localBrowserPath)
        } else {
            sidebarBrowserMode = .games
            localBrowser.clear()
            loadDatabaseSidebarIfNeeded()
        }
        savePreferencesNow()
    }

    func chooseLocalBrowserRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose Local Files Folder"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !localBrowserPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: localBrowserPath, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openLocalBrowserPath(url)
    }

    func openLocalBrowserPath() {
        let panel = NSOpenPanel()
        panel.title = "Open Local Path"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if !localBrowserPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: localBrowserPath, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openLocalBrowserPath(url)
    }

    func openLocalBrowserPath(_ inputURL: URL) {
        let url = inputURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            statusText = "Local path does not exist: \(url.path)"
            return
        }
        let root = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        localBrowserPath = root.path
        localBrowserEnabled = true
        sidebarBrowserMode = .localFiles
        UserDefaults.standard.set(root.path, forKey: AppDefaultsKey.localBrowserPath)
        UserDefaults.standard.set(true, forKey: AppDefaultsKey.localBrowserEnabled)
        configureLocalBrowser(path: root.path)
        if !isDirectory.boolValue { activateLocalBrowserPath(url.path) }
        savePreferencesNow()
    }

    func selectLocalBrowserRow(_ row: LocalBrowserSidebarRow) {
        localBrowser.select(path: row.node.path)
        statusText = row.node.kind == .folder
            ? "Browsing \(row.node.name)"
            : row.node.name
        if row.node.kind == .folder, playlistFollowsCursor {
            queueFolder(URL(fileURLWithPath: row.node.path), replace: true)
        }
    }

    func toggleLocalBrowserFolder(_ path: String) {
        do { try localBrowser.toggleFolder(path: path) }
        catch { statusText = error.localizedDescription }
    }

    func activateLocalBrowserPath(_ path: String, enqueue: Bool = false) {
        guard let url = try? localBrowser.resolve(path: path) else { return }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            queueFolder(url, replace: !enqueue, preservePlayback: !enqueue)
            return
        }
        let generation = queueBuildTaskOwner.begin()
        statusText = "Loading \(url.lastPathComponent)…"
        let task = Task { [weak self] in
            guard let self else { return }
            let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: [url])
            guard self.queueBuildTaskOwner.isCurrent(generation) else { return }
            self.applyQueuedTracks(
                loaded.tracks,
                from: url.deletingLastPathComponent(),
                replace: !enqueue,
                preservePlayback: !enqueue,
                seedMetadataCache: loaded.metadata,
                widthHints: loaded.widthHints,
                autoplay: !enqueue
            )
            self.queueBuildTaskOwner.finish(generation: generation)
        }
        queueBuildTaskOwner.install(task, generation: generation)
    }

    private func configureLocalBrowser(path: String) {
        guard !path.isEmpty else { return }
        do {
            let root = try localBrowser.configure(path: path) {
                PlaybackFormatRegistry.admits(fileURL: $0) || ZipArchiveSupport.canHandle($0)
            }
            statusText = "Browsing local files in \(root.name)"
        } catch {
            localBrowser.clear()
            statusText = error.localizedDescription
        }
    }

    private func loadRoot(url: URL) {
        folderSelectionTaskOwner.cancel()
        rootURL = url
        selectedFolderPath = librarySelectedFolderPath ?? url.path
        librarySelectedFolderPath = selectedFolderPath
        statusText = "Loaded \(url.lastPathComponent)"
        browsedFolderTracks = []
        updateRemoteTransportState()
    }

    func handleFolderSelection(_ folderURL: URL) {
        selectedFolderPath = folderURL.path
        librarySelectedFolderPath = folderURL.path
        let generation = folderSelectionTaskOwner.begin()
        let shouldQueue = playlistFollowsCursor
        statusText = shouldQueue
            ? "Loading \(folderURL.lastPathComponent)..."
            : "Browsing \(folderURL.lastPathComponent)..."

        let task = Task { [weak self] in
            guard let self else { return }
            let tracks = await PlaylistQueueLoader.loadTracks(in: folderURL)
            guard !Task.isCancelled else { return }
            guard self.folderSelectionTaskOwner.isCurrent(generation),
                  self.selectedFolderPath == folderURL.path else {
                return
            }

            self.browsedFolderTracks = tracks
            if shouldQueue {
                self.applyQueuedTracks(tracks, from: folderURL, replace: true)
            } else {
                self.statusText = tracks.isEmpty
                    ? "No supported tracks in \(folderURL.lastPathComponent)"
                    : "Browsing \(tracks.count) tracks in \(folderURL.lastPathComponent)"
            }
            self.folderSelectionTaskOwner.finish(generation: generation)
        }
        folderSelectionTaskOwner.install(task, generation: generation)
    }

    func handleSidebarFolderActivation(_ folderURL: URL) {
        switch sidebarDoubleClickAction {
        case .playNow:
            queueFolder(folderURL, replace: true, preservePlayback: true)
        case .enqueue:
            queueFolder(folderURL, replace: false)
        }
    }

    func playNowFolder(_ folderURL: URL) {
        queueFolder(folderURL, replace: true, preservePlayback: true)
    }

    func enqueueFolder(_ folderURL: URL) {
        queueFolder(folderURL, replace: false)
    }

    func handleSidebarTrackActivation(_ trackURL: URL) {
        queueLibraryTracks(forPaths: [trackURL.path], replace: sidebarDoubleClickAction == .playNow)
    }

    func playNowTrack(_ trackURL: URL) {
        handleSidebarTrackActivation(trackURL)
    }

    func enqueueTrack(_ trackURL: URL) {
        queueLibraryTracks(forPaths: [trackURL.path], replace: false)
    }

    func playNowTrack(_ track: TrackItem) {
        applyPlayableTrackActivation(track, replace: true)
    }

    func enqueueTrack(_ track: TrackItem) {
        applyPlayableTrackActivation(track, replace: false)
    }

    func setPlaylistFollowsCursorEnabled(_ enabled: Bool) {
        playlistFollowsCursor = enabled

        if enabled {
            if effectiveSidebarBrowserMode != .files {
                let selectedItems = databaseGameItems.filter { selectedDatabaseGameIDs.contains($0.id) }
                if !selectedItems.isEmpty {
                    activateDatabaseGames(selectedItems, replace: true)
                }
            }
        }
    }

    func selectDatabaseGame(_ item: DatabaseGameItem) {
        applyDatabaseGroupState(.selectGame(groupName: sidebarSystemName(for: item), gameID: item.id))
        selectedDatabaseGameID = item.id
        selectedDatabaseGameIDs = [item.id]
        statusText = DatabaseSidebarPresentation.selectionStatusText(for: item)
    }

    func selectDatabaseGames(ids: [String], primaryID: String?) {
        selectedDatabaseGameIDs = Set(ids)
        selectedDatabaseGameID = primaryID
        let selectedItems = databaseGameItems.filter { selectedDatabaseGameIDs.contains($0.id) }
        if let primaryID,
           let item = selectedItems.first(where: { $0.id == primaryID }) {
            applyDatabaseGroupState(.selectGame(groupName: sidebarSystemName(for: item), gameID: item.id))
        }
        if playlistFollowsCursor, !selectedItems.isEmpty {
            activateDatabaseGames(selectedItems, replace: true)
            return
        }
        if let primaryID,
           let item = databaseGameItems.first(where: { $0.id == primaryID }) {
            statusText = DatabaseSidebarPresentation.selectionStatusText(for: item)
        }
    }

    func activateDatabaseGame(_ item: DatabaseGameItem, replace: Bool) {
        activateDatabaseGames([item], replace: replace)
    }

    func selectDatabaseFiles(ids: [String], primaryID: String?) {
        selectedDatabaseFileIDs = Set(ids)
        selectedDatabaseFileID = primaryID
        selectedDatabaseFileFolders = []
        if let primaryID,
           let item = databaseFileItems.first(where: { $0.id == primaryID }) {
            statusText = "\(item.filename) • \(item.trackCount) tracks"
        }
    }

    func activateDatabaseFile(_ item: DatabaseFileItem, replace: Bool) {
        activateDatabaseFiles([item], replace: replace)
    }

    func showOnDisk(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url.standardizedFileURL])
        statusText = "Showing \(url.lastPathComponent) on disk"
    }

    func showLibraryDatabaseInFinder() {
        let url = URL(fileURLWithPath: configuredLibraryDatabasePath).standardizedFileURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func selectDatabaseFileSidebarItems(
        fileIDs: [String],
        primaryFileID: String?,
        folders: [DatabaseFileSidebarFolder]
    ) {
        selectedDatabaseFileIDs = Set(fileIDs)
        selectedDatabaseFileID = primaryFileID
        selectedDatabaseFileFolders = Set(folders)
        let selectedItems = selectedDatabaseFileIDs.isEmpty
            ? []
            : databaseFileItems.filter { selectedDatabaseFileIDs.contains($0.id) }
        if folders.count == 1, selectedItems.isEmpty, let folder = folders.first {
            statusText = "\(URL(fileURLWithPath: folder.path).lastPathComponent) • folder"
        } else if !selectedItems.isEmpty || !folders.isEmpty {
            statusText = "\(selectedItems.count + folders.count) selected"
        }
    }

    func activateSelectedDatabaseGamesWithReturn() {
        let selectedItems = databaseGameItems.filter { selectedDatabaseGameIDs.contains($0.id) }
        guard !selectedItems.isEmpty else { return }

        if selectedItems.count > 1 {
            activateDatabaseGames(selectedItems, replace: true)
            return
        }

        let item = selectedItems[0]
        switch sidebarDoubleClickAction {
        case .playNow:
            activateDatabaseGames([item], replace: true)
        case .enqueue:
            activateDatabaseGames([item], replace: false)
        }
    }

    func activateSelectedDatabaseFilesWithReturn() {
        let selectedItems = databaseFileItems.filter { selectedDatabaseFileIDs.contains($0.id) }
        let selectedFolders = Array(selectedDatabaseFileFolders)
        guard !selectedItems.isEmpty || !selectedFolders.isEmpty else { return }
        activateDatabaseFileSidebarSelection(
            fileItems: selectedItems,
            folders: selectedFolders,
            replace: true,
            autoplay: true
        )
    }

    func activateDatabaseFileFolder(_ folder: DatabaseFileSidebarFolder) {
        activateDatabaseFileSidebarSelection(fileItems: [], folders: [folder], replace: true, autoplay: true)
    }

    private func activateDatabaseGames(_ items: [DatabaseGameItem], replace: Bool) {
        guard !items.isEmpty else { return }
        let selectedIDs = items.map(\.id)
        selectedDatabaseGameIDs = Set(selectedIDs)
        selectedDatabaseGameID = selectedIDs.last
        let label = items.count == 1 ? items[0].displayName : "\(items.count) games"
        queueDatabaseLibraryTracks(
            request: .games(items),
            label: label,
            sourceURL: URL(fileURLWithPath: label, isDirectory: true),
            replace: replace
        )
    }

    private func activateDatabaseFiles(_ items: [DatabaseFileItem], replace: Bool) {
        guard !items.isEmpty else { return }
        let selectedIDs = items.map(\.id)
        selectedDatabaseFileIDs = Set(selectedIDs)
        selectedDatabaseFileID = selectedIDs.last
        let label = items.count == 1 ? items[0].filename : "\(items.count) files"
        queueDatabaseLibraryTracks(
            request: .files(items),
            label: label,
            sourceURL: URL(fileURLWithPath: label, isDirectory: false),
            replace: replace
        )
    }

    func queueDatabaseFileSidebarSelection(
        _ payload: DatabaseFileSidebarDragPayload,
        replace: Bool
    ) {
        let fileItems = databaseFileItems.filter { payload.fileIDs.contains($0.id) }
        activateDatabaseFileSidebarSelection(fileItems: fileItems, folders: payload.folders, replace: replace)
    }

    func appendDatabaseFileSidebarDrag(_ payload: DatabaseFileSidebarDragPayload) {
        queueDatabaseFileSidebarSelection(payload, replace: false)
    }

    private func activateDatabaseFileSidebarSelection(
        fileItems: [DatabaseFileItem],
        folders: [DatabaseFileSidebarFolder],
        replace: Bool,
        autoplay: Bool = false
    ) {
        guard !fileItems.isEmpty || !folders.isEmpty else { return }
        let itemCount = fileItems.count + folders.count
        let label = itemCount == 1
            ? (fileItems.first?.filename ?? URL(fileURLWithPath: folders[0].path).lastPathComponent)
            : "\(itemCount) items"
        queueDatabaseLibraryTracks(
            request: .fileSidebar(fileItems: fileItems, folders: folders),
            label: label,
            sourceURL: URL(fileURLWithPath: label, isDirectory: false),
            replace: replace,
            autoplay: autoplay
        )
    }

    private func queueDatabaseLibraryTracks(
        request: LibraryPlaylistLoadRequest,
        label: String,
        sourceURL: URL,
        replace: Bool,
        autoplay: Bool = false
    ) {
        let generation = queueBuildTaskOwner.begin()
        statusText = "Loading \(label)..."
        let databaseURL = libraryDatabaseURL
        let startedAt = ContinuousClock.now
        Self.playlistLoadLogger.info("sidebar playlist load began: \(label, privacy: .public)")

        let task = Task { [weak self] in
            guard let self else { return }
            let loaded: LoadedPlaylistData
            do {
                loaded = try await PlaylistQueueLoader.loadLibraryTracks(
                    databaseURL: databaseURL,
                    request: request,
                    preferFoldersOverMetadata: self.preferFoldersOverMetadata
                )
            } catch {
                guard !Task.isCancelled, self.queueBuildTaskOwner.isCurrent(generation) else { return }
                Self.playlistLoadLogger.error(
                    "sidebar database load failed for \(label, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                self.statusText = "Could not load \(label): \(error.localizedDescription)"
                self.queueBuildTaskOwner.finish(generation: generation)
                return
            }
            guard !Task.isCancelled, self.queueBuildTaskOwner.isCurrent(generation) else { return }
            let databaseElapsed = startedAt.duration(to: .now)
            Self.playlistLoadLogger.info(
                "sidebar database load finished: \(loaded.tracks.count) tracks in \(String(describing: databaseElapsed), privacy: .public)"
            )
            let applyStartedAt = ContinuousClock.now
            self.applyQueuedTracks(
                loaded.tracks,
                from: sourceURL,
                replace: replace,
                preservePlayback: replace && !autoplay,
                seedMetadataCache: loaded.metadata,
                widthHints: loaded.widthHints,
                autoplay: autoplay
            )
            let applyElapsed = applyStartedAt.duration(to: .now)
            Self.playlistLoadLogger.info(
                "sidebar queue applied: \(loaded.tracks.count) tracks in \(String(describing: applyElapsed), privacy: .public)"
            )
            self.statusText = replace
                ? "Queued \(loaded.tracks.count) tracks from \(label) • read \(Self.milliseconds(databaseElapsed)) ms • publish \(Self.milliseconds(applyElapsed)) ms"
                : "Enqueued \(loaded.tracks.count) tracks from \(label) • read \(Self.milliseconds(databaseElapsed)) ms • publish \(Self.milliseconds(applyElapsed)) ms"
            self.queueBuildTaskOwner.finish(generation: generation)
        }
        queueBuildTaskOwner.install(task, generation: generation)
    }

    func queueFolder(_ folderURL: URL, replace: Bool = true, preservePlayback: Bool = false) {
        if let rootPath = libraryRootPath(for: folderURL) {
            queueLibraryFolder(folderURL, rootPath: rootPath, replace: replace, preservePlayback: preservePlayback)
            return
        }

        let generation = queueBuildTaskOwner.begin()
        statusText = "Loading \(folderURL.lastPathComponent)..."

        let task = Task { [weak self] in
            guard let self else { return }
            let tracks = await PlaylistQueueLoader.loadTracks(in: folderURL)
            guard !Task.isCancelled else { return }
            guard self.queueBuildTaskOwner.isCurrent(generation) else { return }
            self.applyQueuedTracks(tracks, from: folderURL, replace: replace, preservePlayback: preservePlayback)
            self.queueBuildTaskOwner.finish(generation: generation)
        }
        queueBuildTaskOwner.install(task, generation: generation)
    }

    func importDroppedURLs(_ urls: [URL]) {
        let normalizedURLs = urls.map(\.standardizedFileURL).filter(PlaylistQueueLoader.canImportDroppedURL(_:))
        guard !normalizedURLs.isEmpty else {
            statusText = "Drop contains no supported files."
            return
        }

        let generation = queueBuildTaskOwner.begin()
        let sourceLabel = normalizedURLs.count == 1
            ? normalizedURLs[0].lastPathComponent
            : "\(normalizedURLs.count) dropped items"
        statusText = "Importing \(sourceLabel)..."

        let task = Task { [weak self] in
            guard let self else { return }
            let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: normalizedURLs)
            guard !Task.isCancelled else { return }
            guard self.queueBuildTaskOwner.isCurrent(generation) else { return }
            guard !loaded.tracks.isEmpty else {
                self.statusText = "No supported tracks in \(sourceLabel)"
                self.queueBuildTaskOwner.finish(generation: generation)
                return
            }

            self.appendTracksToPlaylist(
                loaded.tracks,
                status: "Imported \(loaded.tracks.count) track\(loaded.tracks.count == 1 ? "" : "s") from \(sourceLabel)",
                seedMetadataCache: loaded.metadata,
                widthHints: loaded.widthHints
            )
            self.queueBuildTaskOwner.finish(generation: generation)
        }
        queueBuildTaskOwner.install(task, generation: generation)
    }

    private func applyQueuedTracks(
        _ tracks: [TrackItem],
        from folderURL: URL,
        replace: Bool,
        preservePlayback: Bool = false,
        seedMetadataCache: [String: TrackMetadata] = [:],
        widthHints: PlaylistColumnWidthHints? = nil,
        autoplay: Bool = false
    ) {
        guard !tracks.isEmpty else {
            statusText = "No supported tracks in \(folderURL.lastPathComponent)"
            return
        }

        metadataCache = seedMetadataCache
        playlistColumnWidthHints = widthHints

        if replace {
            let hadFadedSkip = fadedSkipToken != nil
            cancelFadedSkip()
            if !preservePlayback {
                playbackRequestState.cancel()
                isLoading = false
                let playback = self.playback
                Task {
                    await playback.stopPlayback()
                }
                isPlaying = false
                currentTrack = nil
                currentMetadata = nil
                playbackElapsedSeconds = 0
                seekPreviewSeconds = 0
                didAutoAdvanceForCurrentTrack = false
            } else {
                // The current decoder may belong to the previous queue. Re-arm
                // its one-shot completion so the replacement queue takes over
                // when that decoder reaches its real end.
                didAutoAdvanceForCurrentTrack = false
                if hadFadedSkip {
                    let playback = self.playback
                    Task { await playback.restoreOutputGain() }
                }
            }
            playlist = Self.deduplicatedTracks(tracks)
            syncManualPlaylistOrder()
            reapplyPlaylistSortIfNeeded()
            let replacementState = playbackQueueState.replacing(
                playlistIDs: playlist.map(\.id),
                preservePlayback: preservePlayback
            )
            selectedTrackID = replacementState.selectedTrackID
            selectedTrackIDs = selectedTrackID.map { [$0] } ?? []
        } else {
            appendTracksToPlaylist(
                tracks,
                status: "Queued \(tracks.count) tracks from \(folderURL.lastPathComponent)",
                seedMetadataCache: seedMetadataCache,
                widthHints: widthHints
            )
            return
        }

        refreshPlaylistMetadata()
        statusText = "Queued \(tracks.count) tracks from \(folderURL.lastPathComponent)"
        updateRemoteTransportState()
        if autoplay, let firstTrack = playlist.first {
            requestPlayback(for: firstTrack)
        }
    }

    private func appendTracksToPlaylist(
        _ tracks: [TrackItem],
        status: String,
        seedMetadataCache: [String: TrackMetadata] = [:],
        widthHints: PlaylistColumnWidthHints? = nil
    ) {
        var existing = Set(playlist.map(\.id))
        let uniqueTracks = tracks.filter { existing.insert($0.id).inserted }
        guard !uniqueTracks.isEmpty else {
            statusText = status
            return
        }
        metadataCache.merge(seedMetadataCache) { current, _ in current }
        if let widthHints {
            playlistColumnWidthHints = widthHints
        } else if !seedMetadataCache.isEmpty {
            playlistColumnWidthHints = nil
        }
        playlist.append(contentsOf: uniqueTracks)
        syncManualPlaylistOrder()
        reapplyPlaylistSortIfNeeded()
        if selectedTrackID == nil {
            selectedTrackID = playlist.first?.id
            selectedTrackIDs = selectedTrackID.map { [$0] } ?? []
        }
        refreshPlaylistMetadata()
        statusText = status
        updateRemoteTransportState()
    }

    func handleTrackSelection(_ trackID: String?) {
        guard let trackID else { return }
        selectedTrackIDs = [trackID]
    }

    func handlePlaylistSelection(trackIDs: [String], primaryTrackID: String?) {
        selectedTrackIDs = Set(trackIDs)
        selectedTrackID = primaryTrackID
    }

    var allowsManualPlaylistReordering: Bool {
        playlistSortColumn == nil || playlistSortColumn == .index
    }

    var canCutSelectedTracks: Bool {
        !orderedSelectedPlaylistTracks().isEmpty
    }

    var canPasteTracks: Bool {
        !playlistClipboard.isEmpty
    }

    var canShowSelectedTracksInFinder: Bool {
        !orderedSelectedPlaylistTracks().isEmpty
    }

    var canDragReorderTracks: Bool {
        allowsManualPlaylistReordering &&
            !selectedTrackIDs.isEmpty
    }

    var canMoveSelectedTracksUp: Bool {
        guard allowsManualPlaylistReordering else { return false }
        guard let firstSelectedIndex = playlist.firstIndex(where: { selectedTrackIDs.contains($0.id) }) else { return false }
        return firstSelectedIndex > 0
    }

    var canMoveSelectedTracksDown: Bool {
        guard allowsManualPlaylistReordering else { return false }
        guard let lastSelectedIndex = playlist.lastIndex(where: { selectedTrackIDs.contains($0.id) }) else { return false }
        return lastSelectedIndex < playlist.index(before: playlist.endIndex)
    }

    func togglePlaylistSort(by column: PlaylistSortColumn) {
        let nextDirection: PlaylistSortDirection
        if playlistSortColumn == column {
            var toggled = playlistSortDirection
            toggled.toggle()
            nextDirection = toggled
        } else {
            nextDirection = .ascending
        }

        playlistSortColumn = column
        playlistSortDirection = nextDirection
        applyPlaylistSort(column: column, direction: nextDirection)
        AppSessionPersistence.savePlaylistSortState(
            columnRawValue: playlistSortColumn?.rawValue,
            directionRawValue: playlistSortDirection.rawValue
        )
    }

    func cutSelectedTracks() {
        let tracks = orderedSelectedPlaylistTracks()
        guard !tracks.isEmpty else { return }
        playlistClipboard = tracks
        removeTracks(withIDs: Set(tracks.map(\.id)), status: "Cut \(tracks.count) track\(tracks.count == 1 ? "" : "s")")
    }

    func deleteSelectedTracks() {
        let tracks = orderedSelectedPlaylistTracks()
        guard !tracks.isEmpty else { return }
        removeTracks(withIDs: Set(tracks.map(\.id)), status: "Removed \(tracks.count) track\(tracks.count == 1 ? "" : "s")")
    }

    func pasteTracksFromClipboard() {
        guard !playlistClipboard.isEmpty else { return }

        let existingIDs = Set(playlist.map(\.id))
        let tracksToInsert = playlistClipboard.filter { !existingIDs.contains($0.id) }
        guard !tracksToInsert.isEmpty else { return }

        let insertionIndex: Int
        if let selectedTrackID,
           let selectedIndex = playlist.firstIndex(where: { $0.id == selectedTrackID }) {
            insertionIndex = min(selectedIndex + 1, playlist.count)
        } else {
            insertionIndex = playlist.count
        }

        playlist.insert(contentsOf: tracksToInsert, at: insertionIndex)
        syncManualPlaylistOrder()
        reapplyPlaylistSortIfNeeded()
        selectedTrackIDs = Set(tracksToInsert.map(\.id))
        selectedTrackID = tracksToInsert.last?.id
        metadataCache = [:]
        playlistColumnWidthHints = nil
        refreshPlaylistMetadata()
        statusText = "Inserted \(tracksToInsert.count) track\(tracksToInsert.count == 1 ? "" : "s")"
        updateRemoteTransportState()
    }

    func showSelectedTracksInFinder() {
        let tracks = orderedSelectedPlaylistTracks()
        guard !tracks.isEmpty else { return }

        NSWorkspace.shared.activateFileViewerSelecting(tracks.map(\.url))
        statusText = "Showing \(tracks.count) track\(tracks.count == 1 ? "" : "s") in Finder"
    }

    func savePreferencesNow() {
        AppSessionPersistence.savePlaybackPreferences(
            longPlayEnabled: longPlayEnabled,
            playlistFollowsCursor: playlistFollowsCursor,
            manualPreFadeSeconds: manualPreFadeSeconds,
            unknownDurationSeconds: unknownDurationSeconds,
            endFadeEnabled: endFadeEnabled,
            fadeSeconds: configuredFadeSeconds,
            fadedSkipEnabled: fadedSkipEnabled,
            equalizerEnabled: equalizerEnabled,
            equalizerBandGains: equalizerBandGains,
            appVolume: appVolume,
            monoEnabled: monoEnabled,
            randomPlaybackScopeRawValue: randomPlaybackScope.rawValue,
            repeatModeRawValue: repeatMode.rawValue,
            sidebarDoubleClickActionRawValue: sidebarDoubleClickAction.rawValue,
            databaseSidebarFontSize: databaseSidebarFontSize,
            databaseSidebarTextColor: databaseSidebarTextColor.rawValue,
            databaseSidebarMonospaceFont: databaseSidebarMonospaceFont,
            databaseSidebarDisclosureGapPoints: databaseSidebarDisclosureGapPoints,
            databaseSidebarChildIndentPoints: databaseSidebarChildIndentPoints,
            databaseSidebarHidesFileExtensions: databaseSidebarHidesFileExtensions,
            playlistFontSize: playlistFontSize,
            playlistTextColor: playlistTextColor.rawValue,
            playlistMonospaceFont: playlistMonospaceFont,
            sidebarSystemMode: sidebarSystemMode,
            preferEmbeddedConsoleTags: preferEmbeddedConsoleTags,
            sidebarBrowserModeRawValue: sidebarBrowserMode.rawValue,
            libgmeTempo: libgmeTempo,
            libgmeTempoEnabled: libgmeTempoEnabled,
            libvgmTempo: libvgmTempo,
            libvgmTempoEnabled: libvgmTempoEnabled
        )
    }

    func setDatabaseSidebarFontSize(_ size: CGFloat) {
        interfaceFontSize = min(max(size.rounded(), 6), 18)
        savePreferencesNow()
    }

    func setEqualizerBandGain(_ gain: Float, at index: Int) {
        guard equalizerBandGains.indices.contains(index) else { return }
        equalizerBandGains[index] = AudioEqualizer.clampedGain(gain)
        playbackStorage?.setEqualizer(enabled: equalizerEnabled, bandGains: equalizerBandGains)
    }

    func setEqualizerEnabled(_ enabled: Bool) {
        equalizerEnabled = enabled
        savePreferencesNow()
    }

    func setAppVolume(_ volume: Float) {
        appVolume = AudioOutputVolume.clamped(volume)
        savePreferencesNow()
    }

    func setMonoEnabled(_ enabled: Bool) {
        monoEnabled = enabled
        savePreferencesNow()
    }

    func setSidebarDoubleClickAction(_ action: SidebarDoubleClickAction) {
        sidebarDoubleClickAction = action
        savePreferencesNow()
    }

    func resetEqualizer() {
        equalizerBandGains = AudioEqualizer.bandFrequencies.map { _ in Float.zero }
        playbackStorage?.setEqualizer(enabled: equalizerEnabled, bandGains: equalizerBandGains)
    }

    func toggleEqualizerEnabled() {
        equalizerEnabled.toggle()
        savePreferencesNow()
    }

    func setEndFadeEnabled(_ enabled: Bool) {
        endFadeEnabled = enabled
        savePreferencesNow()
        if currentTrack != nil {
            applyPlaybackTiming()
        }
    }

    func setFadeSeconds(_ seconds: Int) {
        configuredFadeSeconds = max(0, seconds)
        savePreferencesNow()
        if currentTrack != nil {
            applyPlaybackTiming()
        }
    }

    func setLibGmeTempo(_ tempo: PlaybackTempo) {
        libgmeTempo = tempo
        savePreferencesNow()
        applyPlaybackTempoIfNeeded(for: "libgme")
    }

    func setLibGmeTempoEnabled(_ enabled: Bool) {
        libgmeTempoEnabled = enabled
        savePreferencesNow()
        applyPlaybackTempoIfNeeded(for: "libgme")
    }

    func setLibVgmTempo(_ tempo: PlaybackTempo) {
        libvgmTempo = tempo
        savePreferencesNow()
        applyPlaybackTempoIfNeeded(for: "libvgm")
    }

    func setLibVgmTempoEnabled(_ enabled: Bool) {
        libvgmTempoEnabled = enabled
        savePreferencesNow()
        applyPlaybackTempoIfNeeded(for: "libvgm")
    }

    func setFadedSkipEnabled(_ enabled: Bool) {
        fadedSkipEnabled = enabled
        if !enabled { cancelFadedSkip() }
        savePreferencesNow()
    }

    func setDatabaseSidebarTextColor(_ color: DatabaseSidebarTextColor) {
        interfaceTextColor = color
        savePreferencesNow()
    }

    func setDatabaseSidebarMonospaceFont(_ enabled: Bool) {
        interfaceMonospaceFont = enabled
        savePreferencesNow()
    }

    func setDatabaseSidebarDisclosureGapPoints(_ gap: CGFloat) {
        databaseSidebarDisclosureGapPoints = min(max(gap, 0), 16)
        savePreferencesNow()
    }

    func setDatabaseSidebarChildIndentPoints(_ indent: CGFloat) {
        databaseSidebarChildIndentPoints = min(max(indent.rounded(), 0), 32)
        savePreferencesNow()
    }

    func setDatabaseSidebarHidesFileExtensions(_ enabled: Bool) {
        databaseSidebarHidesFileExtensions = enabled
        savePreferencesNow()
    }

    func setPlaylistFontSize(_ size: CGFloat) {
        setDatabaseSidebarFontSize(size)
    }

    func setPlaylistTextColor(_ color: DatabaseSidebarTextColor) {
        setDatabaseSidebarTextColor(color)
    }

    func setPlaylistMonospaceFont(_ enabled: Bool) {
        setDatabaseSidebarMonospaceFont(enabled)
    }

    func setSidebarSystemMode(_ enabled: Bool) {
        sidebarSystemMode = enabled
        let groups = enabled && effectiveSidebarBrowserMode == .games && !sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Set(visibleDatabaseGameItems.map { sidebarSystemName(for: $0) })
            : []
        applyDatabaseGroupState(.replaceExpandedGroups(groups))
        savePreferencesNow()
    }

    var preferFoldersOverMetadata: Bool {
        !preferEmbeddedConsoleTags
    }

    func setPreferFoldersOverMetadata(_ enabled: Bool) {
        guard preferFoldersOverMetadata != enabled else { return }
        preferEmbeddedConsoleTags = !enabled
        savePreferencesNow()
        reloadDatabaseSidebar()
    }

    func setSidebarBrowserMode(_ mode: SidebarBrowserMode) {
        if localBrowserEnabled, mode != .localFiles {
            statusText = "Turn off Local Files in Options to use the database library."
            return
        }
        sidebarBrowserMode = mode
        applySidebarSearch()
        if mode != .localFiles { loadDatabaseSidebarIfNeeded() }
        savePreferencesNow()
    }

    /// Replaces the playlist with a snapshot of shared Favorites without
    /// changing the catalog/sidebar mode. Favorites are a playlist projection,
    /// not a third catalog browser.
    func showFavoritesPlaylist() {
        playlist = favoriteTracks
        applyFavoriteMetadata()
        selectedTrackID = playlist.first?.id
        selectedTrackIDs = selectedTrackID.map { [$0] } ?? []
        statusText = playlist.isEmpty ? "No favorites yet." : "Showing \(playlist.count) favorite tracks."
    }

    func cycleLibrarySidebarMode() {
        guard !localBrowserEnabled else { return }
        let modes: [SidebarBrowserMode] = [.games, .files]
        let index = modes.firstIndex(of: sidebarBrowserMode) ?? -1
        setSidebarBrowserMode(modes[(index + 1) % modes.count])
    }

    private func applyFavoriteMetadata() {
        metadataCache = Dictionary(uniqueKeysWithValues: zip(favoriteTracks, displayedFavoriteRecords).map { track, record in
            (track.id, TrackMetadata(
                game: record.game,
                song: record.title,
                system: record.system,
                author: record.author,
                comment: "",
                introLengthMs: 0,
                loopLengthMs: 0,
                playLengthMs: record.playLengthMilliseconds,
                fadeLengthMs: 0
            ))
        })
    }

    func isFavorite(_ track: TrackItem) -> Bool {
        favoriteRecords.contains { $0.identity.id == favoriteIdentity(for: track).id }
    }

    func toggleFavorites() {
        let selected = playlist.filter { selectedTrackIDs.contains($0.id) }
        if !selected.isEmpty {
            toggleFavorites(for: selected, metadata: metadataCache)
            return
        }
        let selectedGames = databaseGameItems.filter { selectedDatabaseGameIDs.contains($0.id) }
        guard !selectedGames.isEmpty else { return }
        Task { [weak self] in
            guard let self, let databaseURL = self.libraryDatabaseURL else { return }
            do {
                let loaded = try await PlaylistQueueLoader.loadLibraryTracksForGames(
                    databaseURL: databaseURL,
                    gameItems: selectedGames,
                    preferFoldersOverMetadata: self.preferFoldersOverMetadata
                )
                self.toggleFavorites(for: loaded.tracks, metadata: loaded.metadata)
            } catch {
                self.statusText = "Could not favorite selection: (error.localizedDescription)"
            }
        }
    }

    func toggleFavorites(for track: TrackItem) {
        toggleFavorites(for: [track], metadata: metadataCache)
    }

    func toggleFavorites(for game: DatabaseGameItem) {
        Task { [weak self] in
            guard let self, let databaseURL = self.libraryDatabaseURL else { return }
            do {
                let loaded = try await PlaylistQueueLoader.loadLibraryTracksForGames(
                    databaseURL: databaseURL,
                    gameItems: [game],
                    preferFoldersOverMetadata: self.preferFoldersOverMetadata
                )
                self.toggleFavorites(for: loaded.tracks, metadata: loaded.metadata)
            } catch {
                self.statusText = "Could not favorite album: \(error.localizedDescription)"
            }
        }
    }

    private func toggleFavorites(for tracks: [TrackItem], metadata: [String: TrackMetadata]) {
        let snapshots = tracks.map { track in
            let trackMetadata = metadata[track.id] ?? self.metadataCache[track.id]
            let identity = favoriteIdentity(for: track)
            return FavoriteTrackSnapshot(
                identity: identity,
                filename: track.filename,
                title: trackMetadata?.song ?? track.displayName,
                game: trackMetadata?.game ?? track.groupDisplayName,
                author: trackMetadata?.author ?? "",
                system: trackMetadata?.system ?? "",
                playLengthMilliseconds: trackMetadata?.playLengthMs ?? 0
            )
        }
        do {
            let mutation = try favorites.toggle(snapshots)
            statusText = tracks.count == 1
                ? (mutation.added ? "Added to Favorites." : "Removed from Favorites.")
                : "Updated Favorites for \(tracks.count) tracks."
        } catch {
            statusText = "Could not update shared Favorites: \(error.localizedDescription)"
        }
    }

    private func favoriteIdentity(for track: TrackItem) -> FavoriteTrackIdentity {
        FavoriteTrackIdentity(
            sourcePath: track.url.path,
            archiveEntry: track.archiveEntryPath,
            trackIndex: track.trackIndex,
            trackCount: track.trackCount
        )
    }

    private func restoreFavorites() {
        do {
            try favorites.restore()
        } catch {
            statusText = "Shared Favorites unavailable: \(error.localizedDescription)"
        }
    }

    func refreshSharedFavorites() {
        do {
            guard try favorites.refreshIfChanged() else { return }
        } catch {
            statusText = "Could not refresh shared Favorites: \(error.localizedDescription)"
        }
    }

    func refreshArchiveCacheSummary() {
        guard !isClearingArchiveCache else { return }
        archiveCacheSummaryTask?.cancel()
        archiveCacheSummaryTask = Task { [weak self] in
            let summary = await Task.detached(priority: .utility) {
                ZipArchiveSupport.cacheSummary()
            }.value
            guard !Task.isCancelled else { return }
            self?.archiveCacheSummaryText = Self.archiveCacheSummaryText(for: summary)
        }
    }

    func setArchiveCacheEnabled(_ enabled: Bool) {
        archiveCachePolicy = ArchiveCachePolicy(
            mode: enabled ? .enabled : .disabled,
            maximumBytes: archiveCachePolicy.maximumBytes
        )
        archiveCachePolicy.save()
        refreshArchiveCacheSummary()
    }

    func setArchiveCacheLimitBytes(_ bytes: Int64) {
        archiveCachePolicy = ArchiveCachePolicy(
            mode: archiveCachePolicy.mode,
            maximumBytes: ArchiveCachePolicy.supportedLimits.min(by: {
                abs($0 - bytes) < abs($1 - bytes)
            }) ?? ArchiveCachePolicy.defaultLimitBytes
        )
        archiveCachePolicy.save()
        refreshArchiveCacheSummary()
    }

    func clearArchiveCache() {
        guard !isClearingArchiveCache else { return }
        isClearingArchiveCache = true
        archiveCacheSummaryTask?.cancel()
        playlistMetadataTaskOwner.cancel()
        let playback = playbackStorage

        archiveCacheClearTask = Task { [weak self] in
            if let playback {
                await playback.stopPlayback()
            }
            do {
                try await Task.detached(priority: .utility) {
                    try ZipArchiveSupport.clearCache()
                }.value
                guard !Task.isCancelled else { return }
                self?.isPlaying = false
                self?.playbackReachedEnd = false
                self?.statusText = "Archive cache cleared."
            } catch {
                self?.statusText = "Could not clear archive cache: \(error.localizedDescription)"
            }
            self?.isClearingArchiveCache = false
            self?.refreshArchiveCacheSummary()
        }
    }

    func showArchiveCacheInFinder() {
        let url = ZipArchiveSupport.cacheDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url.standardizedFileURL])
    }

    func toggleDatabaseFileFolder(_ folderID: String) {
        databaseFileSidebar.toggleFolder(folderID)
    }

    func expandDatabaseFileFolder(_ folderID: String) {
        databaseFileSidebar.expandFolder(folderID)
    }

    private static func archiveCacheSummaryText(for summary: ZipArchiveSupport.CacheSummary) -> String {
        let fileLabel = summary.fileCount == 1 ? "file" : "files"
        let usage = "\(summary.displaySize) • \(summary.fileCount) cached \(fileLabel)"
        guard let availableBytes = summary.availableBytes else { return usage }
        return "\(usage) • \(ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)) free"
    }

    func toggleDatabaseSystemExpansion(_ systemName: String) {
        applyDatabaseGroupState(.toggleGroup(systemName))
    }

    private func applyDatabaseGroupState(_ action: CatalogBrowserGroupState.Action) {
        databaseGroupState = databaseGroupState.applying(action)
        expandedDatabaseSystems = databaseGroupState.expandedGroupNames
    }

    func sidebarSystemName(for item: DatabaseGameItem) -> String {
        item.systemName.isEmpty ? "Unknown System" : item.systemName
    }

    func moveSelectedTracksUp() {
        let selected = orderedSelectedPlaylistTracks()
        guard !selected.isEmpty else { return }

        for track in selected {
            guard let index = playlist.firstIndex(of: track), index > 0 else { continue }
            let previous = playlist.index(before: index)
            if !selectedTrackIDs.contains(playlist[previous].id) {
                playlist.swapAt(previous, index)
            }
        }

        syncManualPlaylistOrder()
        statusText = "Moved \(selected.count) track\(selected.count == 1 ? "" : "s") up"
    }

    func moveSelectedTracksDown() {
        let selected = Array(orderedSelectedPlaylistTracks().reversed())
        guard !selected.isEmpty else { return }

        for track in selected {
            guard let index = playlist.firstIndex(of: track), index < playlist.index(before: playlist.endIndex) else { continue }
            let next = playlist.index(after: index)
            if !selectedTrackIDs.contains(playlist[next].id) {
                playlist.swapAt(index, next)
            }
        }

        syncManualPlaylistOrder()
        statusText = "Moved \(selected.count) track\(selected.count == 1 ? "" : "s") down"
    }

    func moveSelectedTracks(toPlaylistIndex targetIndex: Int) {
        let selected = orderedSelectedPlaylistTracks()
        guard !selected.isEmpty else { return }

        let selectedIDs = Set(selected.map(\.id))
        let boundedTarget = max(0, min(targetIndex, playlist.count))
        let removedBeforeTarget = playlist[..<boundedTarget].filter { selectedIDs.contains($0.id) }.count
        let insertionIndex = boundedTarget - removedBeforeTarget

        let remaining = playlist.filter { !selectedIDs.contains($0.id) }
        var reordered = remaining
        reordered.insert(contentsOf: selected, at: max(0, min(insertionIndex, reordered.count)))
        playlist = reordered

        syncManualPlaylistOrder()
        statusText = "Moved \(selected.count) track\(selected.count == 1 ? "" : "s")"
    }

    private func applyPlaylistSort(
        column: PlaylistSortColumn,
        direction: PlaylistSortDirection,
        updateStatus: Bool = true
    ) {
        let manualOrder = playlistManualOrder
        let metadata = metadataCache
        let sorted = playlist.enumerated().sorted { lhs, rhs in
            let comparison = Self.compareTracks(
                lhs.element,
                rhs.element,
                by: column,
                manualOrder: manualOrder,
                metadata: metadata
            )
            if comparison == .orderedSame {
                return lhs.offset < rhs.offset
            }
            return direction == .ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }.map(\.element)

        playlist = sorted
        if updateStatus {
            statusText = "Sorted queue by \(column.title)"
        }
    }

    private func reapplyPlaylistSortIfNeeded() {
        guard let playlistSortColumn else { return }
        applyPlaylistSort(column: playlistSortColumn, direction: playlistSortDirection)
    }

    func togglePlayback() {
        if isLoading {
            return
        }

        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    func handleMediaPlayPauseCommand() {
        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    func handleMediaPlayCommand() {
        resumePlayback()
    }

    func handleMediaPauseCommand() {
        pausePlayback()
    }

    func pausePlayback() {
        guard !isLoading, currentTrack != nil else { return }
        cancelFadedSkip()
        let playback = self.playback
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = await playback.setPlaying(false)
            self.statusText = "Paused"
            self.updateRemoteTransportState()
        }
    }

    func resumePlayback() {
        guard !isLoading else { return }

        guard let currentTrack else {
            guard let track = transportPlaybackTarget else { return }
            currentTrack = track
            requestPlayback(for: track)
            return
        }

        if !isPlaying, playbackElapsedSeconds == 0 {
            requestPlayback(for: currentTrack)
            return
        }

        let playback = self.playback
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = await playback.setPlaying(true)
            self.statusText = "Playing"
            self.updateRemoteTransportState()
        }
    }

    func toggleTrackPlayback(_ track: TrackItem) {
        if currentTrack?.id == track.id, isPlaying {
            cancelFadedSkip()
            playbackRequestState.cancel()
            isLoading = false
            let playback = self.playback
            Task {
                await playback.stopPlayback()
            }
            isPlaying = false
            isSeeking = false
            playbackElapsedSeconds = 0
            seekPreviewSeconds = 0
            statusText = "Stopped"
            updateRemoteTransportState()
            return
        }

        currentTrack = track
        didAutoAdvanceForCurrentTrack = false
        requestPlayback(for: track)
    }

    func playNext() {
        if randomPlaybackScope == .library {
            playRandomLibraryTrackWhenReady()
            return
        }
        if randomPlaybackScope == .playlist, let randomTrack = randomPlaybackTarget() {
            requestPlayback(for: randomTrack)
            return
        }
        guard let nextTrackID = playbackQueueState.adjacentTargetID(
            playlistIDs: playlist.map(\.id),
            direction: .next,
            wraps: true
        ), let nextTrack = playlist.first(where: { $0.id == nextTrackID }) else { return }
        requestAdjacentPlayback(nextTrack)
    }

    func cycleRandomPlaybackScope() {
        switch randomPlaybackScope {
        case .off: randomPlaybackScope = .library
        case .library: randomPlaybackScope = .playlist
        case .playlist: randomPlaybackScope = .off
        }
        if randomPlaybackScope == .library {
            loadRandomLibraryTracks()
        } else {
            randomLibraryPlaybackPending = false
            randomLibraryLoadTaskOwner.cancel()
            if randomPlaybackScope == .off { randomLibraryTracks = [] }
        }
        savePreferencesNow()
    }

    private func randomPlaybackTarget() -> TrackItem? {
        let candidates = randomPlaybackScope == .library ? randomLibraryTracks : visiblePlaylist
        guard !candidates.isEmpty else { return nil }
        let eligible = candidates.filter { $0.id != currentTrack?.id }
        return (eligible.isEmpty ? candidates : eligible).randomElement()
    }

    private func playRandomLibraryTrackWhenReady() {
        if let randomTrack = randomPlaybackTarget() {
            startRandomLibraryPlayback(randomTrack)
            return
        }

        randomLibraryPlaybackPending = true
        statusText = "Loading Random Library…"
        loadRandomLibraryTracks()
    }

    private func loadRandomLibraryTracks() {
        guard randomPlaybackScope == .library, !randomLibraryLoadTaskOwner.isActive else { return }
        guard let databaseURL = libraryDatabaseURL, !databaseGameItems.isEmpty else {
            if randomLibraryPlaybackPending {
                randomLibraryPlaybackPending = false
                statusText = "Random Library has no playable tracks."
            }
            return
        }
        guard let item = randomLibraryGame() else {
            randomLibraryPlaybackPending = false
            statusText = "Random Library has no playable tracks."
            return
        }
        let generation = randomLibraryLoadTaskOwner.begin()
        let preferFoldersOverMetadata = self.preferFoldersOverMetadata
        let task = Task { [weak self] in
            let loaded: LoadedPlaylistData
            do {
                loaded = try await PlaylistQueueLoader.loadLibraryTracksForGames(
                    databaseURL: databaseURL,
                    gameItems: [item],
                    preferFoldersOverMetadata: preferFoldersOverMetadata
                )
            } catch {
                guard let self,
                      self.randomPlaybackScope == .library,
                      self.randomLibraryLoadTaskOwner.isCurrent(generation) else { return }
                Self.playlistLoadLogger.error(
                    "random library load failed: \(error.localizedDescription, privacy: .public)"
                )
                self.randomLibraryLoadTaskOwner.finish(generation: generation)
                if self.randomLibraryPlaybackPending {
                    self.randomLibraryPlaybackPending = false
                    self.statusText = "Could not load Random Library: \(error.localizedDescription)"
                }
                return
            }
            guard let self,
                  self.randomPlaybackScope == .library,
                  self.randomLibraryLoadTaskOwner.isCurrent(generation) else { return }
            self.randomLibraryTracks = loaded.tracks
            self.randomLibraryLoadTaskOwner.finish(generation: generation)
            guard self.randomLibraryPlaybackPending else { return }
            self.randomLibraryPlaybackPending = false
            guard let randomTrack = self.randomPlaybackTarget() else {
                self.statusText = "Random Library has no playable tracks."
                return
            }
            self.startRandomLibraryPlayback(randomTrack)
        }
        randomLibraryLoadTaskOwner.install(task, generation: generation)
    }

    private func startRandomLibraryPlayback(_ track: TrackItem) {
        randomLibraryTracks = []
        requestPlayback(for: track)
        loadRandomLibraryTracks()
    }

    private func randomLibraryGame() -> DatabaseGameItem? {
        let candidates = databaseGameItems.filter { $0.trackCount > 0 }
        let totalWeight = candidates.reduce(Int64(0)) { partial, item in
            partial + Int64(item.trackCount)
        }
        guard totalWeight > 0 else { return nil }

        var offset = Int64.random(in: 0..<totalWeight)
        for item in candidates {
            let weight = Int64(item.trackCount)
            if offset < weight { return item }
            offset -= weight
        }
        return candidates.last
    }

    func handleMediaNextCommand() {
        playNext()
    }

    func playPrevious() {
        guard let previousTrackID = playbackQueueState.adjacentTargetID(
            playlistIDs: playlist.map(\.id),
            direction: .previous,
            wraps: true
        ), let previousTrack = playlist.first(where: { $0.id == previousTrackID }) else { return }
        requestAdjacentPlayback(previousTrack)
    }

    private func requestAdjacentPlayback(_ track: TrackItem) {
        guard let fadeDuration = PlaybackFadePolicy.queuedSkipDuration(
            enabled: fadedSkipEnabled,
            isPlaying: isPlaying,
            hasCurrentTrack: currentTrack != nil,
            elapsedSeconds: playbackElapsedSeconds,
            preFadeSeconds: Double(effectivePreFadeSeconds),
            fadeSeconds: Double(fadeSeconds),
            totalSeconds: Double(totalPlaybackSeconds)
        ) else {
            requestPlayback(for: track)
            return
        }

        // A second adjacent command abandons the long musical fade and lets
        // ordinary replacement perform only its 10 ms de-click transition.
        guard fadedSkipToken == nil else {
            cancelFadedSkip()
            requestPlayback(for: track)
            return
        }

        let token = UUID()
        fadedSkipToken = token
        let playback = self.playback
        fadedSkipTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let sessionGeneration = await playback.beginFadedSkip(duration: fadeDuration),
                  self.fadedSkipToken == token else {
                if self.fadedSkipToken == token {
                    self.cancelFadedSkip()
                    self.requestPlayback(for: track)
                }
                return
            }
            self.statusText = "Fading to \(track.filename)…"
            do {
                try await Task.sleep(for: .seconds(fadeDuration))
            } catch {
                return
            }
            guard self.fadedSkipToken == token,
                  await playback.isCurrentGeneration(sessionGeneration) else {
                return
            }
            self.fadedSkipTask = nil
            self.fadedSkipToken = nil
            self.requestPlayback(for: track)
        }
    }

    private func cancelFadedSkip() {
        fadedSkipTask?.cancel()
        fadedSkipTask = nil
        fadedSkipToken = nil
    }

    func handleMediaPreviousCommand() {
        playPrevious()
    }

    func replayCurrentTrack() {
        guard let currentTrack else { return }
        requestPlayback(for: currentTrack)
    }

    func handleManualPlaySecondsChanged() {
        manualPreFadeSeconds = max(30, manualPreFadeSeconds)
        if longPlayEnabled && currentTrackSupportsLongPlay {
            applyPlaybackTiming()
        }
    }

    func setUnknownDurationSeconds(_ seconds: Int) {
        unknownDurationSeconds = max(1, seconds)
        savePreferencesNow()
        if currentTrack != nil {
            applyPlaybackTiming()
        }
    }

    func toggleLongPlayEnabled() {
        savePreferencesNow()
        if currentTrackSupportsLongPlay {
            applyPlaybackTiming()
        }
    }

    func applyPlaybackTiming() {
        guard let currentTrack, !isLoading else { return }
        let plan = playbackPlan(for: currentMetadata, trackPathExtension: currentTrack.playablePathExtension)
        isLoading = true
        statusText = "Updating Long Play…"
        let playback = self.playback
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await playback.reconfigureCurrentTrack(plan: plan, tempo: self.playbackTempo(for: currentTrack))
                let snapshot = await playback.statusSnapshot()
                self.playbackElapsedSeconds = snapshot.elapsedSeconds
                self.seekPreviewSeconds = snapshot.elapsedSeconds
                self.isPlaying = snapshot.isPlaying
                self.statusText = "Long Play updated"
            } catch {
                self.statusText = error.localizedDescription
            }
            self.isLoading = false
            self.updateRemoteTransportState()
        }
    }

    private func applyPlaybackTempoIfNeeded(for backendID: String) {
        guard let currentTrack,
              FormatRegistry.family(for: currentTrack.playablePathExtension)?.id == backendID,
              !isLoading else { return }
        let plan = playbackPlan(for: currentMetadata, trackPathExtension: currentTrack.playablePathExtension)
        let tempo = playbackTempo(for: currentTrack)
        isLoading = true
        statusText = "Updating tempo…"
        let playback = self.playback
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await playback.reconfigureCurrentTrack(plan: plan, tempo: tempo)
                let snapshot = await playback.statusSnapshot()
                self.playbackElapsedSeconds = snapshot.elapsedSeconds
                self.seekPreviewSeconds = snapshot.elapsedSeconds
                self.isPlaying = snapshot.isPlaying
                self.statusText = "Tempo updated"
            } catch {
                self.statusText = error.localizedDescription
            }
            self.isLoading = false
            self.updateRemoteTransportState()
        }
    }

    func playSelectedTrack() {
        guard let selectedTrackID, let track = playlist.first(where: { $0.id == selectedTrackID }) else { return }
        currentTrack = track
        requestPlayback(for: track)
    }

    func playTrack(_ track: TrackItem) {
        currentTrack = track
        selectedTrackID = track.id
        selectedTrackIDs = [track.id]
        requestPlayback(for: track)
    }

    func beginSeek() {
        isSeeking = true
        seekPreviewSeconds = playbackElapsedSeconds
    }

    func completeSeek() {
        let hadFadedSkip = fadedSkipToken != nil
        cancelFadedSkip()
        let target = seekPreviewSeconds
        isSeeking = false
        let playback = self.playback
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if hadFadedSkip {
                    await playback.restoreOutputGain()
                }
                try await playback.seek(to: target)
                self.playbackElapsedSeconds = target
                self.updateRemoteTransportState()
            } catch {
                self.statusText = error.localizedDescription
            }
        }
    }

    private func requestPlayback(for track: TrackItem) {
        cancelFadedSkip()
        if isLoading, currentTrack?.id == track.id {
            return
        }

        playlistMetadataTaskOwner.cancel()
        let generation = playbackRequestState.begin(track: track)
        isLoading = true
        statusText = "Rendering \(track.filename)..."

        let playback = self.playback
        let requestID = playback.reservePlaybackRequest()
        let task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            guard let self, self.playbackRequestState.isCurrent(generation) else { return }
            await self.play(track: track, generation: generation, requestID: requestID)
        }
        playbackRequestState.install(task, generation: generation)
    }

    private func play(track: TrackItem, generation: Int, requestID: Int) async {
        isLoading = true
        statusText = "Rendering \(track.filename)..."

        do {
            try Task.checkCancellation()
            let isNewTrack = await playback.currentTrackID() != track.id
            let cachedMetadata = metadataCache[track.id]
            let seedMetadata: TrackMetadata? = if !isNewTrack, let currentMetadata {
                currentMetadata
            } else if let cachedMetadata {
                cachedMetadata
            } else {
                nil
            }

            try Task.checkCancellation()
            guard playbackRequestState.isCurrent(generation) else { return }

            let plan = playbackPlan(for: seedMetadata, trackPathExtension: track.playablePathExtension)
            try await playback.play(track: track, plan: plan, tempo: playbackTempo(for: track), requestID: requestID)
            guard playbackRequestState.isCurrent(generation) else { return }
            currentTrack = track
            pendingPlaybackTrack = nil
            currentMetadata = seedMetadata
            if let seedMetadata {
                updatePlaylistMetadata(for: track.id, metadata: seedMetadata)
            }
            isPlaying = true
            didAutoAdvanceForCurrentTrack = false
            playbackElapsedSeconds = 0
            seekPreviewSeconds = 0

            let songTitle = seedMetadata?.song.nonEmpty ?? track.displayName
            let gameTitle = seedMetadata?.game.nonEmpty ?? track.groupDisplayName
            statusText = "\(gameTitle) • \(songTitle)"
            updateRemoteTransportState()
        } catch is CancellationError {
            if playbackRequestState.isCurrent(generation) {
                isPlaying = await playback.statusSnapshot().isPlaying
                updateRemoteTransportState()
            }
        } catch {
            guard playbackRequestState.isCurrent(generation) else { return }
            isPlaying = false
            statusText = error.localizedDescription
            updateRemoteTransportState()
        }

        finishPlaybackRequest(generation: generation)
    }

    private func finishPlaybackRequest(generation: Int) {
        guard playbackRequestState.isCurrent(generation) else { return }
        isLoading = false
        playbackRequestState.finish(generation: generation)
        refreshPlaylistMetadata()
    }

    var currentSongTitle: String {
        if let currentMetadata, !currentMetadata.song.isEmpty {
            return currentMetadata.song
        }
        return currentTrack?.displayName ?? "CocoaSpice"
    }

    var currentGameTitle: String {
        if let currentMetadata, !currentMetadata.game.isEmpty {
            return currentMetadata.game
        }
        return currentTrack?.groupDisplayName ?? rootURL?.lastPathComponent ?? ""
    }

    var statusSystemText: String {
        currentMetadata?.system.nonEmpty ?? "Game Music"
    }

    var statusAuthorText: String {
        currentMetadata?.author.nonEmpty ?? "—"
    }

    var statusCommentText: String {
        currentMetadata?.comment.nonEmpty ?? statusText
    }

    var hasLoopMetadata: Bool {
        guard let currentMetadata else { return false }
        return currentMetadata.loopLengthMs > 0
    }

    var currentTrackSupportsLongPlay: Bool {
        guard let extensionName = currentTrack?.playablePathExtension else { return true }
        return PlaybackFormatRegistry.supportsLongPlay(pathExtension: extensionName)
    }

    private func playbackTempo(for track: TrackItem) -> PlaybackTempo {
        playbackTempo(forPathExtension: track.playablePathExtension)
    }

    private func playbackTempo(forPathExtension pathExtension: String?) -> PlaybackTempo {
        guard let pathExtension,
              let family = FormatRegistry.family(for: "source.\(pathExtension)"),
              family.supportsTempo else {
            return .defaultValue
        }
        switch family.id {
        case "libgme": return libgmeTempoEnabled ? libgmeTempo : .defaultValue
        case "libvgm": return libvgmTempoEnabled ? libvgmTempo : .defaultValue
        default: return .defaultValue
        }
    }

    var effectivePreFadeSeconds: Int {
        playbackPlan(for: currentMetadata, trackPathExtension: currentTrack?.playablePathExtension).preFadeSeconds
    }

    var totalPlaybackSeconds: Int {
        effectivePreFadeSeconds + fadeSeconds
    }

    var currentTrackDurationReadout: String {
        Self.formatTime(totalPlaybackSeconds)
    }

    var elapsedReadout: String {
        Self.formatTime(Int(displayedElapsedSeconds.rounded()))
    }

    /// Recompute only when the playlist or its metadata changes. SwiftUI reads
    /// this value on every body pass, so deriving it there made the status bar
    /// walk every track continuously at idle.
    private func refreshPlaylistTotalDurationReadout() {
        playlistDurationTrackIDs = Set(playlist.map(\.id))
        playlistDurationSecondsByTrackID = [:]
        playlistDurationTotalSeconds = 0
        for track in playlist {
            guard let milliseconds = metadataCache[track.id]?.playLengthMs,
                  milliseconds > 0 else { continue }
            let tempo = playbackTempo(for: track)
            let seconds = max(1, Int((Double(milliseconds) / 1_000 / tempo.multiplier).rounded(.down)))
            playlistDurationSecondsByTrackID[track.id] = seconds
            playlistDurationTotalSeconds += seconds
        }
        updatePlaylistTotalDurationReadout()
    }

    private func updatePlaylistDuration(for trackID: TrackItem.ID, metadata: TrackMetadata) {
        guard playlistDurationTrackIDs.contains(trackID) else { return }
        let previous = playlistDurationSecondsByTrackID[trackID] ?? 0
        let tempo = playlist.first(where: { $0.id == trackID }).map(playbackTempo(for:)) ?? .defaultValue
        let updated = max(0, Int((Double(max(metadata.playLengthMs, 0)) / 1_000 / tempo.multiplier).rounded(.down)))
        if updated > 0 {
            playlistDurationSecondsByTrackID[trackID] = updated
        } else {
            playlistDurationSecondsByTrackID.removeValue(forKey: trackID)
        }
        playlistDurationTotalSeconds += updated - previous
    }

    private func updatePlaylistTotalDurationReadout() {
        let isPartial = playlistDurationSecondsByTrackID.count != playlistDurationTrackIDs.count
        let readout = "\(Self.formatTime(playlistDurationTotalSeconds))\(isPartial ? "+" : "")"
        if playlistTotalDurationReadout != readout {
            playlistTotalDurationReadout = readout
        }
    }

    var statusPathReadout: String {
        let track = currentTrack ?? transportPlaybackTarget
        guard let track else { return "" }
        return track.statusPathText
    }

    var visiblePlaylist: [TrackItem] {
        playlist
    }

    var preFadeReadout: String {
        PlaylistPresentation.formatTime(effectivePreFadeSeconds)
    }

    var manualModeReadout: String {
        PlaylistPresentation.formatTime(manualPreFadeSeconds)
    }

    var displayedElapsedSeconds: TimeInterval {
        isSeeking ? seekPreviewSeconds : playbackElapsedSeconds
    }

    var sliderRangeUpperBound: Double {
        max(1, Double(totalPlaybackSeconds))
    }

    private var playbackQueueState: PlaybackQueueState {
        PlaybackQueueState(
            currentTrackID: currentTrack?.id,
            selectedTrackID: selectedTrackID,
            pendingTrackID: pendingPlaybackTrack?.id
        )
    }

    private var transportPlaybackTarget: TrackItem? {
        guard let targetID = playbackQueueState.transportTargetID(
            playlistIDs: playlist.map(\.id)
        ) else { return nil }
        return playlist.first(where: { $0.id == targetID })
    }

    private func playbackPlan(for metadata: TrackMetadata?, trackPathExtension: String? = nil) -> PlaybackPlan {
        let plan = PlaybackTimingPolicy.playbackPlan(
            metadata: metadata ?? currentMetadata,
            trackPathExtension: trackPathExtension ?? currentTrack?.playablePathExtension,
            longPlayEnabled: longPlayEnabled,
            manualPreFadeSeconds: manualPreFadeSeconds,
            fadeSeconds: fadeSeconds,
            unknownDurationSeconds: unknownDurationSeconds
        )
        let tempo = playbackTempo(forPathExtension: trackPathExtension ?? currentTrack?.playablePathExtension)
        guard tempo != .defaultValue else { return plan }
        let scaledPreFade = max(1, Int((Double(plan.preFadeSeconds) / tempo.multiplier).rounded(.down)))
        return PlaybackPlan(
            preFadeSeconds: scaledPreFade,
            fadeSeconds: plan.fadeSeconds,
            usesNativeEnding: plan.usesNativeEnding,
            isLongPlay: plan.isLongPlay,
            unknownDurationSeconds: plan.unknownDurationSeconds
        )
    }

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Do not create the full audio graph merely to poll idle UI
                // state at launch. Playback initializes on the first actual
                // request, then this timer observes its live session.
                guard let playback = self.playbackStorage else { return }
                self.playbackDiagnostics = playback.diagnosticsSnapshot()
                let snapshot = await playback.statusSnapshot()
                if !self.isSeeking {
                    self.playbackElapsedSeconds = snapshot.elapsedSeconds
                }
                self.updateRemoteTransportState()
            }
        }
    }

    private func handlePlaybackCompletionIfNeeded() {
        guard !isLoading,
              !isSeeking,
              fadedSkipToken == nil,
              !isPlaying,
              !didAutoAdvanceForCurrentTrack,
              currentTrack != nil,
              !playlist.isEmpty else {
            return
        }

        // Only the drained native output may declare completion. Elapsed-time
        // thresholds can mistake a pause or a short/unknown duration for EOF.
        guard playbackReachedEnd else { return }

        didAutoAdvanceForCurrentTrack = true
        if randomPlaybackScope == .library {
            playRandomLibraryTrackWhenReady()
            return
        }
        if randomPlaybackScope == .playlist, let randomTrack = randomPlaybackTarget() {
            requestPlayback(for: randomTrack)
            return
        }
        guard let sharedRepeatMode = PlaybackRepeatMode(rawValue: repeatMode.rawValue) else {
            return
        }
        let decision = playbackQueueState.completionDecision(
            playlistIDs: playlist.map(\.id),
            repeatMode: sharedRepeatMode
        )
        guard case let .play(nextTrackID) = decision.action,
              let nextTrack = playlist.first(where: { $0.id == nextTrackID }) else {
            return
        }
        requestPlayback(for: nextTrack)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .playlist
        case .playlist: repeatMode = .song
        case .song: repeatMode = .off
        }
        savePreferencesNow()
    }

    private func libraryRootPath(for folderURL: URL) -> String? {
        let normalizedFolderPath = folderURL.standardizedFileURL.path
        return enabledCatalogRootURLs
            .map(\.path)
            .first(where: { normalizedFolderPath == $0 || normalizedFolderPath.hasPrefix($0 + "/") })
    }

    private func queueLibraryFolder(_ folderURL: URL, rootPath: String, replace: Bool, preservePlayback: Bool) {
        let generation = queueBuildTaskOwner.begin()
        statusText = "Loading \(folderURL.lastPathComponent)..."
        let databaseURL = libraryDatabaseURL
        let folderPath = folderURL.path

        let task = Task { [weak self] in
            guard let self else { return }
            let loaded: LoadedPlaylistData
            do {
                loaded = try await PlaylistQueueLoader.loadLibraryTracksForFolder(
                    databaseURL: databaseURL,
                    rootPath: rootPath,
                    folderPath: folderPath
                )
            } catch {
                guard !Task.isCancelled, self.queueBuildTaskOwner.isCurrent(generation) else { return }
                Self.playlistLoadLogger.error(
                    "library folder load failed: \(error.localizedDescription, privacy: .public)"
                )
                self.statusText = "Could not load \(folderURL.lastPathComponent): \(error.localizedDescription)"
                self.queueBuildTaskOwner.finish(generation: generation)
                return
            }
            guard !Task.isCancelled, self.queueBuildTaskOwner.isCurrent(generation) else { return }
            self.applyQueuedTracks(
                loaded.tracks,
                from: folderURL,
                replace: replace,
                preservePlayback: preservePlayback,
                seedMetadataCache: loaded.metadata,
                widthHints: loaded.widthHints
            )
            self.queueBuildTaskOwner.finish(generation: generation)
        }
        queueBuildTaskOwner.install(task, generation: generation)
    }

    private func queueLibraryTracks(forPaths paths: [String], replace: Bool) {
        let normalizedPaths = Array(NSOrderedSet(array: paths.map {
            URL(fileURLWithPath: $0, isDirectory: false).standardizedFileURL.path
        })) as? [String] ?? []
        guard !normalizedPaths.isEmpty else { return }

        let generation = queueBuildTaskOwner.begin()
        let label = normalizedPaths.count == 1
            ? URL(fileURLWithPath: normalizedPaths[0]).lastPathComponent
            : "\(normalizedPaths.count) files"
        statusText = "Loading \(label)..."
        let databaseURL = libraryDatabaseURL

        let task = Task { [weak self] in
            guard let self else { return }
            let loaded: LoadedPlaylistData
            do {
                loaded = try await PlaylistQueueLoader.loadLibraryTracksForPaths(
                    databaseURL: databaseURL,
                    paths: normalizedPaths
                )
            } catch {
                guard !Task.isCancelled, self.queueBuildTaskOwner.isCurrent(generation) else { return }
                Self.playlistLoadLogger.error(
                    "library path load failed for \(label, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                self.statusText = "Could not load \(label): \(error.localizedDescription)"
                self.queueBuildTaskOwner.finish(generation: generation)
                return
            }
            guard !Task.isCancelled, self.queueBuildTaskOwner.isCurrent(generation) else { return }
            self.applyQueuedTracks(
                loaded.tracks,
                from: URL(fileURLWithPath: label, isDirectory: false),
                replace: replace,
                preservePlayback: replace,
                seedMetadataCache: loaded.metadata,
                widthHints: loaded.widthHints
            )
            if replace, let firstTrack = loaded.tracks.first {
                self.currentTrack = firstTrack
                self.selectedTrackID = firstTrack.id
                self.requestPlayback(for: firstTrack)
            }
            self.queueBuildTaskOwner.finish(generation: generation)
        }
        queueBuildTaskOwner.install(task, generation: generation)
    }

    private func applyPlayableTrackActivation(_ track: TrackItem, replace: Bool) {
        if replace {
            applyQueuedTracks([track], from: track.revealURL, replace: true, preservePlayback: true)
            currentTrack = track
            selectedTrackID = track.id
            requestPlayback(for: track)
        } else {
            appendTracksToPlaylist([track], status: "Enqueued 1 track from \(track.groupDisplayName)")
        }
    }

    private func refreshPlaylistMetadata(limit _: Int? = nil) {
        let generation = playlistMetadataTaskOwner.begin()
        let tracks = playlist
        let cachedMetadata = metadataCache

        guard !tracks.isEmpty else {
            playlistColumnWidthHints = nil
            playlistMetadataLoadToken += 1
            playlistMetadataTaskOwner.finish(generation: generation)
            return
        }

        // Catalog rows are the sole metadata contract. CocoaSpice never
        // opens a decoder to repair or enrich them; incomplete catalog fields
        // must be corrected by a later MediaScanner publication.
        playlistColumnWidthHints = Self.buildPlaylistColumnWidthHints(
            tracks: tracks,
            metadata: cachedMetadata
        )
        if playlistSortDependsOnMetadata(playlistSortColumn),
           let sortColumn = playlistSortColumn {
            applyPlaylistSort(
                column: sortColumn,
                direction: playlistSortDirection,
                updateStatus: false
            )
        }
        playlistMetadataLoadToken += 1
        playlistMetadataTaskOwner.finish(generation: generation)
    }

    private func updatePlaylistMetadata(_ updates: [TrackItem.ID: TrackMetadata]) {
        guard !updates.isEmpty else { return }
        metadataCache.merge(updates) { _, replacement in replacement }
        for (trackID, metadata) in updates {
            updatePlaylistDuration(for: trackID, metadata: metadata)
        }
        updatePlaylistTotalDurationReadout()
        if playlistMetadataRefreshWorkItem == nil {
            playlistMetadataChangedTrackIDs.removeAll(keepingCapacity: true)
        }
        playlistMetadataChangedTrackIDs.formUnion(updates.keys)
        schedulePlaylistMetadataTableRefresh()
    }

    private func updatePlaylistMetadata(for trackID: TrackItem.ID, metadata: TrackMetadata) {
        updatePlaylistMetadata([trackID: metadata])
    }

    private func schedulePlaylistMetadataTableRefresh() {
        guard playlistMetadataRefreshWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.playlistMetadataRefreshWorkItem = nil
            self.playlistMetadataLoadToken += 1
        }
        playlistMetadataRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: workItem)
    }

    private func syncManualPlaylistOrder() {
        var order: [TrackItem.ID: Int] = [:]
        for (index, track) in playlist.enumerated() where order[track.id] == nil {
            order[track.id] = index
        }
        playlistManualOrder = order
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds * 1_000) + Int(components.attoseconds / 1_000_000_000_000_000)
    }

    private static func deduplicatedTracks(_ tracks: [TrackItem]) -> [TrackItem] {
        var seen = Set<TrackItem.ID>()
        return tracks.filter { seen.insert($0.id).inserted }
    }

    private func reloadCatalogRoots() {
        guard let databaseURL = libraryDatabaseURL else { return }
        do {
            catalogRoots = try CatalogBrowser.roots(databaseURL: databaseURL)
        } catch {
            libraryDatabaseLocationStatus = "Could not load catalog roots: \(error.localizedDescription)"
        }
    }

    private func reloadDatabaseSidebar() {
        databaseSidebarLoader.invalidateAndLoad(
            databaseURL: libraryDatabase?.databaseURL,
            mode: effectiveSidebarBrowserMode,
            preferFoldersOverMetadata: preferFoldersOverMetadata,
            didLoadGames: { [weak self] in self?.databaseGamesDidLoad() },
            didLoadFiles: { [weak self] in self?.databaseFilesDidLoad() }
        )
    }

    private func loadDatabaseSidebarIfNeeded() {
        databaseSidebarLoader.loadIfNeeded(
            databaseURL: libraryDatabase?.databaseURL,
            mode: effectiveSidebarBrowserMode,
            preferFoldersOverMetadata: preferFoldersOverMetadata,
            didLoadGames: { [weak self] in self?.databaseGamesDidLoad() },
            didLoadFiles: { [weak self] in self?.databaseFilesDidLoad() }
        )
    }

    private func databaseGamesDidLoad() {
        finishLibraryReloadIfNeeded()
        if sidebarSystemMode,
           !sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyDatabaseGroupState(.replaceExpandedGroups(Set(visibleDatabaseGameItems.map { sidebarSystemName(for: $0) })))
        }
        if randomPlaybackScope == .library {
            randomLibraryTracks = []
            randomLibraryLoadTaskOwner.cancel()
            loadRandomLibraryTracks()
        }
    }

    private func databaseFilesDidLoad() {
        finishLibraryReloadIfNeeded()
        applyDatabaseFileSidebarSearch()
    }

    private func finishLibraryReloadIfNeeded() {
        guard libraryDatabaseLocationStatus?.hasPrefix("Reloading the current MediaScanner catalog") == true else { return }
        libraryDatabaseLocationStatus = "Library reloaded from the current MediaScanner catalog."
    }

    private func syncActiveRootToCatalogRoots(preferredRoot: URL? = nil) {
        let enabledRoots = catalogRoots.filter(\.isEnabled)

        guard !enabledRoots.isEmpty else {
            resetSidebarContext(message: "No library paths configured.")
            return
        }

        let preferred = preferredRoot?.standardizedFileURL
        if let preferred,
           enabledRoots.contains(where: { $0.standardizedURL == preferred }),
           rootURL?.standardizedFileURL != preferred {
            loadRoot(url: preferred)
            return
        }

        if let rootURL,
           enabledRoots.contains(where: { $0.standardizedURL == rootURL.standardizedFileURL }) {
            return
        }

        loadRoot(url: enabledRoots[0].standardizedURL)
    }

    private func clearLibraryState() {
        folderSelectionTaskOwner.cancel()
        queueBuildTaskOwner.cancel()
        rootURL = nil
        selectedFolderPath = nil
        databaseSidebarLoader.clear()
        browsedFolderTracks = []
        playlist = []
        syncManualPlaylistOrder()
        metadataCache = [:]
        refreshPlaylistTotalDurationReadout()
        playlistColumnWidthHints = nil
        selectedTrackID = nil
        currentTrack = nil
        pendingPlaybackTrack = nil
        currentMetadata = nil
        playbackElapsedSeconds = 0
        seekPreviewSeconds = 0
        isPlaying = false
        statusText = "No library paths configured."
    }

    private func resetSidebarContext(message: String) {
        folderSelectionTaskOwner.cancel()
        queueBuildTaskOwner.cancel()
        rootURL = nil
        selectedFolderPath = nil
        databaseSidebar.clearSelection()
        databaseFileSidebar.clearSelection()
        browsedFolderTracks = []
        sidebarSearchText = ""
        playlistColumnWidthHints = nil
        statusText = message
    }

    private func restorePlaybackPreferences(_ preferences: RestoredPlaybackPreferences) {
        longPlayEnabled = preferences.longPlayEnabled
        playlistFollowsCursor = preferences.playlistFollowsCursor
        if let storedManualPreFade = preferences.manualPreFadeSeconds {
            manualPreFadeSeconds = storedManualPreFade
        }
        if let storedUnknownDuration = preferences.unknownDurationSeconds {
            unknownDurationSeconds = max(1, storedUnknownDuration)
        }
        endFadeEnabled = preferences.endFadeEnabled
        configuredFadeSeconds = max(0, preferences.fadeSeconds)
        fadedSkipEnabled = preferences.fadedSkipEnabled
        equalizerEnabled = preferences.equalizerEnabled
        if let storedGains = preferences.equalizerBandGains,
           storedGains.count == AudioEqualizer.bandFrequencies.count {
            equalizerBandGains = storedGains.map { AudioEqualizer.clampedGain(Float($0)) }
        }
        appVolume = AudioOutputVolume.clamped(Float(preferences.appVolume))
        monoEnabled = preferences.monoEnabled
        libgmeTempo = preferences.libgmeTempo
        libgmeTempoEnabled = preferences.libgmeTempoEnabled
        libvgmTempo = preferences.libvgmTempo
        libvgmTempoEnabled = preferences.libvgmTempoEnabled
        randomPlaybackScope = RandomPlaybackScope(rawValue: preferences.randomPlaybackScopeRawValue ?? "off") ?? .off
        repeatMode = RepeatMode(rawValue: preferences.repeatModeRawValue ?? "off") ?? .off
        if randomPlaybackScope == .library { loadRandomLibraryTracks() }
        if let storedAction = preferences.sidebarDoubleClickActionRawValue.flatMap(SidebarDoubleClickAction.init(rawValue:)) {
            sidebarDoubleClickAction = storedAction
        }
        if let storedInterfaceFontSize = preferences.databaseSidebarFontSize ?? preferences.playlistFontSize {
            interfaceFontSize = min(max(CGFloat(storedInterfaceFontSize).rounded(), 6), 18)
        }
        if let storedInterfaceTextColor = (preferences.databaseSidebarTextColor ?? preferences.playlistTextColor).flatMap(DatabaseSidebarTextColor.init(rawValue:)) {
            interfaceTextColor = storedInterfaceTextColor
        }
        interfaceMonospaceFont = preferences.databaseSidebarMonospaceFont || preferences.playlistMonospaceFont
        if let storedSidebarDisclosureGapPoints = preferences.databaseSidebarDisclosureGapPoints {
            databaseSidebarDisclosureGapPoints = min(max(CGFloat(storedSidebarDisclosureGapPoints), 0), 16)
        } else if let legacyEmGap = preferences.databaseSidebarDisclosureGap {
            // The brief pre-release implementation stored a font-relative value.
            // Preserve its visual distance once, then persist future edits in points.
            databaseSidebarDisclosureGapPoints = min(max(CGFloat(legacyEmGap) * databaseSidebarFontSize, 0), 16)
        }
        if let storedSidebarChildIndentPoints = preferences.databaseSidebarChildIndentPoints {
            databaseSidebarChildIndentPoints = min(max(CGFloat(storedSidebarChildIndentPoints).rounded(), 0), 32)
        }
        databaseSidebarHidesFileExtensions = preferences.databaseSidebarHidesFileExtensions
        sidebarSystemMode = preferences.sidebarSystemMode
        preferEmbeddedConsoleTags = preferences.preferEmbeddedConsoleTags
        sidebarBrowserMode = SidebarBrowserMode(rawValue: preferences.sidebarBrowserModeRawValue ?? "games") ?? .games
        applySidebarSearch()
        if sidebarSystemMode,
           sidebarBrowserMode == .games,
           !sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyDatabaseGroupState(.replaceExpandedGroups(Set(visibleDatabaseGameItems.map { sidebarSystemName(for: $0) })))
        }
        if let storedSortColumn = preferences.playlistSortColumnRawValue.flatMap(PlaylistSortColumn.init(rawValue:)) {
            playlistSortColumn = storedSortColumn
        }
        if let storedSortDirection = preferences.playlistSortDirectionRawValue.flatMap(PlaylistSortDirection.init(rawValue:)) {
            playlistSortDirection = storedSortDirection
        }
    }

    func saveSessionStateNow() {
        sidebarSearchPersistenceWorkItem?.cancel()
        sidebarSearchPersistenceWorkItem = nil
        AppSessionPersistence.saveSessionState(
            playlist: playlist,
            deferredPersistedValues: deferredPersistedPlaylistValues,
            selectedTrackID: selectedTrackID,
            currentTrackID: currentTrack?.id,
            rootPath: rootURL?.path,
            selectedFolderPath: selectedFolderPath,
            librarySelectedFolderPath: librarySelectedFolderPath,
            sidebarSearchText: sidebarSearchText
        )
        savePreferencesNow()
        AppSessionPersistence.savePlaylistColumnState(
            order: pendingPlaylistColumnOrder,
            visibility: pendingPlaylistColumnVisibility,
            widths: pendingPlaylistColumnWidths
        )
    }

    private func scheduleSidebarSearchPersistence() {
        sidebarSearchPersistenceWorkItem?.cancel()
        let text = sidebarSearchText
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.sidebarSearchText == text else { return }
            UserDefaults.standard.set(text, forKey: AppDefaultsKey.sidebarSearchText)
        }
        sidebarSearchPersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func applySidebarSearch() {
        if sidebarBrowserMode == .localFiles {
            databaseSidebar.searchText = ""
            databaseFileSidebarSearchTaskOwner.cancel()
            return
        }
        let hasQuery = !sidebarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasQuery || sidebarBrowserMode == .games {
            databaseFileSidebarSearchTaskOwner.cancel()
            databaseSidebar.searchText = sidebarSearchQuery
            if sidebarSystemMode {
                applyDatabaseGroupState(.replaceExpandedGroups(hasQuery
                    ? Set(visibleDatabaseGameItems.map { sidebarSystemName(for: $0) })
                    : []))
            }
        } else {
            databaseSidebar.searchText = ""
            applyDatabaseFileSidebarSearch()
        }
        loadDatabaseSidebarIfNeeded()
    }

    private func applyDatabaseFileSidebarSearch() {
        guard databaseSidebarLoader.hasLoadedFiles else { return }
        let query = sidebarSearchQuery
        let items = databaseFileItems
        let searchIndex = databaseFileSidebar.searchIndex
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            databaseFileSidebarSearchTaskOwner.cancel()
            databaseFileSidebar.applySearchResult(query: query, items: items, treeIndex: nil)
            return
        }

        let generation = databaseFileSidebarSearchTaskOwner.begin()
        let task = Task { [weak self] in
            let result = await withTaskGroup(
                of: (items: [DatabaseFileItem], treeIndex: DatabaseFileSidebarTree.Index)?.self,
                returning: (items: [DatabaseFileItem], treeIndex: DatabaseFileSidebarTree.Index)?.self
            ) { group in
                group.addTask(priority: .utility) {
                    guard let filtered = (searchIndex?.filter(
                        query: query,
                        isCancelled: { Task.isCancelled }
                    ) ?? DatabaseFileSidebarTree.filter(
                        items,
                        query: query,
                        isCancelled: { Task.isCancelled }
                    )),
                    let treeIndex = DatabaseFileSidebarTree.Index(
                        items: filtered,
                        isCancelled: { Task.isCancelled }
                    ),
                    !Task.isCancelled else {
                        return nil
                    }
                    return (items: filtered, treeIndex: treeIndex)
                }
                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }
            guard !Task.isCancelled,
                  let self,
                  let result,
                  self.databaseFileSidebarSearchTaskOwner.isCurrent(generation),
                  self.sidebarSearchQuery == query else { return }
            self.databaseFileSidebar.applySearchResult(
                query: query,
                items: result.items,
                treeIndex: result.treeIndex
            )
            self.databaseFileSidebarSearchTaskOwner.finish(generation: generation)
        }
        databaseFileSidebarSearchTaskOwner.install(task, generation: generation)
    }

    private func restorePlaylistColumnState(_ state: RestoredPlaylistColumnState) {
        pendingPlaylistColumnOrder = state.order
        pendingPlaylistColumnVisibility = state.visibility
        pendingPlaylistColumnWidths = state.widths
    }

    private func restorePersistedPlaylist(_ session: RestoredSessionState?) {
        guard let session else { return }
        isRestoringPersistedPlaylist = true
        playlist = session.tracks
        isRestoringPersistedPlaylist = false
        deferredPersistedPlaylistValues = session.deferredPersistedValues
        if let selectedTrackID = session.selectedTrackID {
            self.selectedTrackID = session.tracks.first(where: { $0.id == selectedTrackID })?.id
        }
        if let currentTrackID = session.currentTrackID {
            currentTrack = session.tracks.first(where: { $0.id == currentTrackID })
        }
        syncManualPlaylistOrder()
        reapplyPlaylistSortIfNeeded()
        if selectedTrackID == nil {
            selectedTrackID = session.tracks.first?.id
        }
        if let selectedTrackID {
            selectedTrackIDs = [selectedTrackID]
        }
        metadataCache = [:]
        refreshPlaylistTotalDurationReadout()
        playlistColumnWidthHints = nil
        refreshPlaylistMetadata(limit: 128)
        if session.deferredTrackCount > 0 {
            statusText = "Restored \(session.tracks.count.formatted()) queue tracks; \(session.deferredTrackCount.formatted()) deferred to keep startup responsive"
        }
    }

    private func orderedSelectedPlaylistTracks() -> [TrackItem] {
        playlist.filter { selectedTrackIDs.contains($0.id) }
    }

    private func removeTracks(withIDs ids: Set<String>, status: String) {
        guard !ids.isEmpty else { return }
        playlist.removeAll { ids.contains($0.id) }
        syncManualPlaylistOrder()

        if let selectedTrackID, ids.contains(selectedTrackID) {
            self.selectedTrackID = playlist.first?.id
        }
        selectedTrackIDs.subtract(ids)
        if selectedTrackIDs.isEmpty, let selectedTrackID {
            selectedTrackIDs = [selectedTrackID]
        }

        metadataCache = [:]
        refreshPlaylistTotalDurationReadout()
        playlistColumnWidthHints = nil
        refreshPlaylistMetadata()
        statusText = status
        updateRemoteTransportState()
    }

    func savePlaylistM3U() {
        guard !playlist.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Save Playlist"
        panel.nameFieldStringValue = "Playlist.m3u"
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let contents = PlaylistM3UCodec.encode(playlist)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        statusText = "Saved playlist to \(url.lastPathComponent)"
    }

    func loadPlaylistM3U() {
        let panel = NSOpenPanel()
        panel.title = "Open Playlist"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let m3uType = UTType(filenameExtension: "m3u") {
            panel.allowedContentTypes = [m3uType]
        }
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        openPlaylistM3U(at: url)
    }

    func openPlaylistM3U(at url: URL) {
        guard url.pathExtension.lowercased() == "m3u" else {
            statusText = "Unsupported playlist file: (url.lastPathComponent)"
            return
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let tracks = PlaylistM3UCodec.decode(
            contents,
            baseDirectory: url.deletingLastPathComponent(),
            supportedExtensions: PlaybackFormatRegistry.supportedExtensions
        )

        guard !tracks.isEmpty else { return }
        playbackRequestState.cancel()
        isLoading = false
        let playback = self.playback
        Task {
            await playback.stopPlayback()
        }
        isPlaying = false
        currentTrack = nil
        currentMetadata = nil
        playbackElapsedSeconds = 0
        seekPreviewSeconds = 0
        playlist = tracks
        syncManualPlaylistOrder()
        reapplyPlaylistSortIfNeeded()
        selectedTrackID = tracks.first?.id
        metadataCache = [:]
        refreshPlaylistTotalDurationReadout()
        playlistColumnWidthHints = nil
        refreshPlaylistMetadata()
        statusText = "Loaded playlist \(url.lastPathComponent)"
        updateRemoteTransportState()
    }

    private func restoreInitialSidebarMode(
        lastRootPath: String?,
        lastLibrarySelectedFolderPath: String?
    ) {
        librarySelectedFolderPath = lastLibrarySelectedFolderPath

        let enabledRoots = catalogRoots.filter(\.isEnabled)
        if let lastRootPath,
           let restoredRoot = enabledRoots.first(where: { $0.standardizedURL.path == lastRootPath }) {
            let restoredSelection = lastLibrarySelectedFolderPath
            loadRoot(url: restoredRoot.standardizedURL)
            if let restoredSelection,
               restoredSelection.hasPrefix(restoredRoot.standardizedURL.path) {
                selectedFolderPath = restoredSelection
                librarySelectedFolderPath = restoredSelection
            }
        } else if let firstEnabledRoot = enabledRoots.first {
            let restoredSelection = lastLibrarySelectedFolderPath
            loadRoot(url: firstEnabledRoot.standardizedURL)
            if let restoredSelection,
               restoredSelection.hasPrefix(firstEnabledRoot.standardizedURL.path) {
                selectedFolderPath = restoredSelection
                librarySelectedFolderPath = restoredSelection
            }
        } else {
            rootURL = nil
            selectedFolderPath = nil
            librarySelectedFolderPath = nil
            databaseSidebarLoader.clear()
            browsedFolderTracks = []
            if playlist.isEmpty {
                statusText = "No library paths configured."
            } else {
                statusText = "Restored playlist."
            }
        }
    }

    func rememberPlaylistColumnOrder(_ order: [String]) {
        pendingPlaylistColumnOrder = order
    }

    func rememberPlaylistColumnVisibility(_ visibility: [String: Bool]) {
        pendingPlaylistColumnVisibility = visibility
    }

    func rememberPlaylistColumnWidths(_ widths: [String: Double]) {
        pendingPlaylistColumnWidths = widths
    }

    private func playlistSortDependsOnMetadata(_ column: PlaylistSortColumn?) -> Bool {
        guard let column else { return false }
        switch column {
        case .index, .file, .path:
            return false
        case .title, .game, .author, .system, .length:
            return true
        }
    }

    func titleText(for track: TrackItem) -> String {
        PlaylistPresentation.titleText(for: track, metadata: metadataCache[track.id])
    }

    func gameText(for track: TrackItem) -> String {
        PlaylistPresentation.gameText(for: track, metadata: metadataCache[track.id])
    }

    func authorText(for track: TrackItem) -> String {
        PlaylistPresentation.authorText(for: metadataCache[track.id])
    }

    func systemText(for track: TrackItem) -> String {
        PlaylistPresentation.systemText(for: metadataCache[track.id])
    }

    func lengthText(for track: TrackItem) -> String {
        PlaylistPresentation.lengthText(for: metadataCache[track.id])
    }

    func pathText(for track: TrackItem) -> String {
        let fullPath = track.fullPathText
        let roots = catalogRoots
            .map(\.standardizedURL)
            .sorted { $0.path.count > $1.path.count }
        guard let root = roots.first(where: {
            fullPath == $0.path || fullPath.hasPrefix($0.path + "/")
        }) else {
            return fullPath
        }
        let suffix = String(fullPath.dropFirst(root.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty
            ? root.lastPathComponent
            : "\(root.lastPathComponent)/\(suffix)"
    }

    func indexText(for track: TrackItem) -> String {
        guard let index = playlist.firstIndex(of: track) else { return "—" }
        return String(index + 1)
    }

    nonisolated private static func buildPlaylistColumnWidthHints(
        tracks: [TrackItem],
        metadata: [String: TrackMetadata]
    ) -> PlaylistColumnWidthHints {
        PlaylistPresentation.buildColumnWidthHints(tracks: tracks, metadata: metadata)
    }

    nonisolated private static func compareTracks(
        _ lhs: TrackItem,
        _ rhs: TrackItem,
        by column: PlaylistSortColumn,
        manualOrder: [String: Int],
        metadata: [String: TrackMetadata]
    ) -> ComparisonResult {
        PlaylistPresentation.compareTracks(
            lhs,
            rhs,
            by: column,
            manualOrder: manualOrder,
            metadata: metadata
        )
    }

    nonisolated private static func formatTime(_ totalSeconds: Int) -> String {
        PlaylistPresentation.formatTime(totalSeconds)
    }

    private func updateRemoteTransportState() {
        guard currentTrack != nil || isPlaying || !playlist.isEmpty else { return }
        if !remoteTransportConfigured {
            remoteTransport.configure(
                previous: { [weak self] in self?.handleMediaPreviousCommand() },
                play: { [weak self] in self?.handleMediaPlayCommand() },
                pause: { [weak self] in self?.handleMediaPauseCommand() },
                togglePlayPause: { [weak self] in self?.handleMediaPlayPauseCommand() },
                next: { [weak self] in self?.handleMediaNextCommand() }
            )
            remoteTransportConfigured = true
        }
        remoteTransport.updateNowPlaying(remoteNowPlaying)
    }
}
