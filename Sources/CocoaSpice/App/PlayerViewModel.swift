import AppKit
import Foundation
import OSLog
import Observation
import UniformTypeIdentifiers

enum SidebarBrowserMode: String, CaseIterable, Identifiable {
    case games
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .games: "Games"
        case .files: "Files"
        }
    }

    var iconName: String {
        switch self {
        case .games: "square.grid.2x2"
        case .files: "folder"
        }
    }
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

    private let libraryOperations = LibraryOperationsState()

    var libraryScanRoots: [LibraryScanRoot] {
        get { libraryOperations.scanRoots }
        set { libraryOperations.scanRoots = newValue }
    }
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
        sidebarViewResolution(storedMode: storedMode, searchText: searchText).contentMode == .folders
            ? .files
            : .games
    }

    nonisolated static func sidebarViewResolution(
        storedMode: SidebarBrowserMode,
        searchText: String
    ) -> SidebarViewResolution {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedPresentation: SidebarPresentationView = storedMode == .files ? .folders : .database
        let isSearching = !query.isEmpty
        let view: SidebarPresentationView = isSearching ? .search : storedPresentation
        let contentMode: SidebarPresentationView = view == .folders ? .folders : .database
        return SidebarViewResolution(
            storedMode: storedPresentation,
            query: query,
            view: view,
            contentMode: contentMode,
            resultSource: contentMode == .folders ? "folder-tree" : "database-index",
            isTemporary: isSearching
        )
    }
    private(set) var expandedDatabaseSystems: Set<String> = []
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
    var selectedTrackID: TrackItem.ID?
    var selectedTrackIDs: Set<TrackItem.ID> = []
    private enum PlaylistMetadataInspectionPolicy: Equatable {
        /// The playlist was built from scan-time database rows. Its presentation
        /// must never reopen source files merely to fill in optional fields.
        case databaseSnapshot
        /// Direct imports may inspect source files to fill absent metadata.
        case inspectMissing
    }

    var playlist: [TrackItem] = [] {
        didSet {
            if !isRestoringPersistedPlaylist {
                deferredPersistedPlaylistValues = []
            }
            playlistContentRevision &+= 1
            refreshPlaylistTotalDurationReadout()
        }
    }
    private(set) var playlistContentRevision = 0
    private var isRestoringPersistedPlaylist = false
    private var deferredPersistedPlaylistValues: [String] = []
    var metadataCache: [String: TrackMetadata] = [:]
    private var playlistMetadataInspectionPolicy: PlaylistMetadataInspectionPolicy = .inspectMissing
    private(set) var playlistTotalDurationReadout = "0:00"
    private var playlistDurationSecondsByTrackID: [TrackItem.ID: Int] = [:]
    private var playlistDurationTrackIDs: Set<TrackItem.ID> = []
    private var playlistDurationTotalSeconds = 0
    var playlistColumnWidthHints: PlaylistColumnWidthHints?
    var playlistSortColumn: PlaylistSortColumn?
    var playlistSortDirection: PlaylistSortDirection = .ascending
    var currentTrack: TrackItem?
    var currentMetadata: TrackMetadata?
    let toolbarSpectrum = ToolbarSpectrumModel()
    private static let defaultSpectrumGradientStartColor = NSColor(
        calibratedRed: 0.000000,
        green: 0.976805,
        blue: 0.000000,
        alpha: 1.000000
    )
    private static let defaultSpectrumGradientEndColor = NSColor(
        calibratedRed: 0.016804,
        green: 0.198351,
        blue: 1.000000,
        alpha: 1.000000
    )
    private static let defaultSpectrumPeakColor = NSColor(
        calibratedRed: 1.000000,
        green: 0.149131,
        blue: 0.000000,
        alpha: 1.000000
    )
    var spectrumGradientStartColor = PlayerViewModel.defaultSpectrumGradientStartColor {
        didSet { toolbarSpectrum.gradientStartColor = spectrumGradientStartColor }
    }
    var spectrumGradientEndColor = PlayerViewModel.defaultSpectrumGradientEndColor {
        didSet { toolbarSpectrum.gradientEndColor = spectrumGradientEndColor }
    }
    var spectrumPeakColor = PlayerViewModel.defaultSpectrumPeakColor {
        didSet { toolbarSpectrum.peakColor = spectrumPeakColor }
    }
    var spectrumEnabled = false {
        didSet {
            toolbarSpectrum.isVisible = spectrumEnabled
            playbackStorage?.setSpectrumEnabled(spectrumEnabled)
            if !spectrumEnabled { toolbarSpectrum.setAnimating(false) }
        }
    }
    var spectrumBandCount = SpectrumBandCount.defaultValue {
        didSet {
            toolbarSpectrum.configure(bandCount: spectrumBandCount)
            playbackStorage?.setSpectrumBandCount(spectrumBandCount)
        }
    }
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
    var endFadeEnabled = true
    var fadedSkipEnabled = false
    var fadeSeconds: Int { endFadeEnabled ? 6 : 0 }
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
    var libraryScanStatus: String? {
        get { libraryOperations.status }
        set { libraryOperations.status = newValue }
    }
    private(set) var cleanLibraryScanRootIDs: Set<Int64> {
        get { libraryOperations.cleanRootIDs }
        set { libraryOperations.cleanRootIDs = newValue }
    }
    private(set) var trimmedLibraryScanRootIDs: Set<Int64> {
        get { libraryOperations.trimmedRootIDs }
        set { libraryOperations.trimmedRootIDs = newValue }
    }
    private(set) var libraryScanInProgress: Bool {
        get { libraryOperations.scanInProgress }
        set { libraryOperations.scanInProgress = newValue }
    }
    var forceLibraryScan: Bool {
        get { libraryOperations.forceScan }
        set { libraryOperations.forceScan = newValue }
    }
    var libraryScanProgressByRootID: [Int64: LibraryScanProgress] {
        libraryOperations.scanProgressByRootID
    }
    var libraryScanCurrentPath: String? {
        libraryOperations.scanCurrentPath
    }
    var libraryScanCurrentFile: String? {
        libraryOperations.scanCurrentFile
    }
    private(set) var trimMissingProgress: LibraryScanProgress? {
        get { libraryOperations.linkTestProgress }
        set { libraryOperations.linkTestProgress = newValue }
    }
    private(set) var trimMissingCurrentPath: String? {
        get { libraryOperations.linkTestCurrentPath }
        set { libraryOperations.linkTestCurrentPath = newValue }
    }
    private(set) var archiveCacheSummaryText: String {
        get { libraryOperations.archiveCacheSummaryText }
        set { libraryOperations.archiveCacheSummaryText = newValue }
    }
    private(set) var isClearingArchiveCache: Bool {
        get { libraryOperations.isClearingArchiveCache }
        set { libraryOperations.isClearingArchiveCache = newValue }
    }
    var archiveCachePolicy = ArchiveCachePolicy.load()
    private(set) var deadLinkSummaryText: String {
        get { libraryOperations.deadLinkSummaryText }
        set { libraryOperations.deadLinkSummaryText = newValue }
    }
    private(set) var deadLinkCount: Int {
        get { libraryOperations.deadLinkCount }
        set { libraryOperations.deadLinkCount = newValue }
    }
    private(set) var databaseEntryCount: Int {
        get { libraryOperations.databaseEntryCount }
        set { libraryOperations.databaseEntryCount = newValue }
    }
    private(set) var unlinkedDatabaseEntryCount: Int {
        get { libraryOperations.unlinkedDatabaseEntryCount }
        set { libraryOperations.unlinkedDatabaseEntryCount = newValue }
    }
    private(set) var isDeletingDeadLinks: Bool {
        get { libraryOperations.isDeletingDeadLinks }
        set { libraryOperations.isDeletingDeadLinks = newValue }
    }
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
        }
    }
    var databaseSidebarLoadError: String? {
        switch effectiveSidebarBrowserMode {
        case .games: databaseSidebarLoader.gameLoadError
        case .files: databaseSidebarLoader.fileLoadError
        }
    }

    func retryDatabaseSidebarLoad() {
        loadDatabaseSidebarIfNeeded()
    }

    var enabledLibraryRootURLs: [URL] {
        libraryScanRoots
            .filter(\.isEnabled)
            .map(\.standardizedURL)
    }

    var libraryDatabaseURL: URL? {
        libraryDatabase?.databaseURL
    }

    @ObservationIgnored private var playbackStorage: PlaybackEngine?
    @ObservationIgnored private var remoteTransportStorage: RemoteTransportController?
    @ObservationIgnored private var audioExportWindowController: AudioExportProgressWindowController?
    @ObservationIgnored private var audioExportProgressSnapshot: AudioExportProgressSnapshot?
    @ObservationIgnored private var lastAudioExportDirectoryURL: URL?
    private var remoteTransportConfigured = false
    private let libraryDatabase: LibraryDatabase?
    private var playbackTimer: Timer?
    private let playlistMetadataTaskOwner = LatestTaskOwner()
    private let playbackRequestState = PlaybackRequestState()
    @ObservationIgnored private var libraryScanController: LibraryScanController?
    private let folderSelectionTaskOwner = LatestTaskOwner()
    private let queueBuildTaskOwner = LatestTaskOwner()
    private let randomLibraryLoadTaskOwner = LatestTaskOwner()
    private var audioExportTask: Task<Void, Never>?
    private var archiveCacheSummaryTask: Task<Void, Never>?
    private var archiveCacheClearTask: Task<Void, Never>?
    private let deadLinkSummaryTaskOwner = LatestTaskOwner()
    private var deadLinkCleanupTask: Task<Void, Never>?
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
        playback.setSpectrumLevelHandler { [weak self] levels in
            Task { @MainActor [weak self] in
                self?.toolbarSpectrum.update(with: levels)
            }
        }
        playback.setSpectrumEnabled(spectrumEnabled)
        playback.setSpectrumBandCount(spectrumBandCount)
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
                if !snapshot.isPlaying || !self.spectrumEnabled {
                    self.toolbarSpectrum.setAnimating(false)
                } else {
                    self.toolbarSpectrum.setAnimating(true)
                }
                self.updateRemoteTransportState()
                if snapshot.reachedEnd {
                    self.handlePlaybackCompletionIfNeeded()
                }
            }
        }
        playbackStorage = playback
        return playback
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
            libraryScanStatus = "Library database unavailable: \(error.localizedDescription)"
        }
        if let libraryDatabase {
            libraryScanController = LibraryScanController(
                database: libraryDatabase,
                operations: libraryOperations,
                roots: { [weak self] in self?.libraryScanRoots ?? [] },
                didCompleteRoot: { [weak self] root, _ in
                    guard let self else { return }
                    self.trimmedLibraryScanRootIDs.remove(root.id)
                    self.persistTrimmedLibraryRootIDs()
                    self.reloadLibraryScanRoots()
                    self.reloadDatabaseSidebar()
                    self.refreshDeadLinkSummary()
                },
                didFailRoot: { [weak self] _ in
                    self?.reloadLibraryScanRoots()
                }
            )
        }
        trimmedLibraryScanRootIDs = Set(
            UserDefaults.standard.array(forKey: "trimmedLibraryScanRootIDs")?.compactMap { ($0 as? NSNumber)?.int64Value } ?? []
        )
        toolbarSpectrum.gradientStartColor = spectrumGradientStartColor
        toolbarSpectrum.gradientEndColor = spectrumGradientEndColor
        toolbarSpectrum.peakColor = spectrumPeakColor
        restorePlaybackPreferences(restoredState.playbackPreferences)
        Task { [weak self] in
            let recovery = await Task.detached(priority: .utility) {
                ZipArchiveSupport.reclaimAbandonedScanMaterializations()
            }.value
            guard recovery.rootCount > 0 else { return }
            self?.statusText = "Recovered \(recovery.rootCount) abandoned CocoaSpice cache items (\(ByteCountFormatter.string(fromByteCount: recovery.byteCount, countStyle: .file)))."
        }
        reloadLibraryScanRoots()
        reloadDatabaseSidebar()
        restorePersistedPlaylist(restoredState.sessionState)
        restorePlaylistColumnState(restoredState.playlistColumnState)
        sidebarSearchText = restoredState.sidebarSearchText
        startPlaybackTimer()
        restoreInitialSidebarMode(
            lastRootPath: restoredState.lastRootPath,
            lastLibrarySelectedFolderPath: restoredState.lastLibrarySelectedFolderPath
        )
        updateRemoteTransportState()
    }

    func chooseLibraryScanRoots() {
        let panel = NSOpenPanel()
        panel.title = "Choose Music Scan Roots"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }

        guard let libraryDatabase else {
            libraryScanStatus = "Cannot add scan roots: library database unavailable."
            return
        }

        let addedURLs = panel.urls.map(\.standardizedFileURL)
        let databaseURL = libraryDatabase.databaseURL
        let generation = libraryOperations.beginTask()
        libraryScanInProgress = true
        libraryScanStatus = "Adding library paths…"
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            do {
                try await Task.detached(priority: .utility) {
                    let database = try LibraryDatabase(databaseURL: databaseURL)
                    for url in addedURLs {
                        try database.addRoot(path: url.path)
                    }
                }.value
            } catch {
                guard self.libraryOperations.isCurrentTask(generation) else { return }
                self.libraryScanInProgress = false
                self.libraryScanStatus = "Could not save scan root: \(error.localizedDescription)"
                self.reloadLibraryScanRoots()
                self.libraryOperations.finishTask(generation: generation)
                return
            }

            guard self.libraryOperations.isCurrentTask(generation), !Task.isCancelled else { return }
            self.reloadLibraryScanRoots()
            self.reloadDatabaseSidebar()
            self.syncActiveRootToLibraryScanRoots(preferredRoot: addedURLs.first)
            let addedPaths = Set(addedURLs.map(\.path))
            let addedRoots = self.libraryScanRoots.filter {
                addedPaths.contains($0.standardizedURL.path) && $0.isEnabled
            }
            self.libraryScanInProgress = false
            self.libraryOperations.finishTask(generation: generation)
            self.runModernLibraryScan(for: addedRoots, mode: .incremental)
        }
        libraryOperations.installTask(task, generation: generation)
    }

    func loadLibraryRoot(_ root: LibraryScanRoot) {
        loadRoot(url: root.standardizedURL)
    }

    func activeLibraryRootID() -> Int64? {
        guard let rootURL else { return nil }
        return libraryScanRoots.first(where: { $0.standardizedURL == rootURL.standardizedFileURL })?.id
    }

    var librarySourceSummary: String {
        let enabledRoots = libraryScanRoots.filter(\.isEnabled)
        guard !enabledRoots.isEmpty else { return "No library paths configured." }
        if enabledRoots.count == 1 {
            return enabledRoots[0].path
        }
        return "\(enabledRoots.count) library paths configured"
    }

    var areAllLibraryScanRootsEnabled: Bool {
        !libraryScanRoots.isEmpty && libraryScanRoots.allSatisfy(\.isEnabled)
    }

    func setLibraryScanRootEnabled(_ id: Int64, isEnabled: Bool) {
        guard let index = libraryScanRoots.firstIndex(where: { $0.id == id }),
              libraryScanRoots[index].isEnabled != isEnabled else {
            return
        }
        libraryScanRoots[index].isEnabled = isEnabled
        syncActiveRootToLibraryScanRoots()
        persistLibraryRootEnabledStatesAfterInteraction()
    }

    func toggleAllLibraryScanRootsEnabled() {
        guard !libraryScanRoots.isEmpty else { return }
        let isEnabled = !areAllLibraryScanRootsEnabled
        for index in libraryScanRoots.indices {
            libraryScanRoots[index].isEnabled = isEnabled
        }
        syncActiveRootToLibraryScanRoots()
        persistLibraryRootEnabledStatesAfterInteraction()
    }

    func removeLibraryScanRoot(_ id: Int64) {
        guard !libraryScanInProgress,
              let databaseURL = libraryDatabase?.databaseURL,
              let root = libraryScanRoots.first(where: { $0.id == id }) else { return }
        let generation = libraryOperations.beginTask()
        libraryScanInProgress = true
        libraryScanStatus = "Removing \(root.standardizedURL.lastPathComponent)…"

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.libraryOperations.isCurrentTask(generation) {
                    self.libraryScanInProgress = false
                    self.libraryOperations.finishTask(generation: generation)
                }
            }
            await Task.yield()
            let errorDescription = await Task.detached(priority: .utility) { () -> String? in
                do {
                    try LibraryDatabase(databaseURL: databaseURL).detachRoot(id: id)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            guard self.libraryOperations.isCurrentTask(generation), !Task.isCancelled else { return }
            if let errorDescription {
                self.libraryScanStatus = "Could not remove path: \(errorDescription)"
                return
            }
            self.libraryScanController?.closeLiveLog(rootID: id)
            self.reloadLibraryScanRoots()
            self.reloadDatabaseSidebar()
            self.syncActiveRootToLibraryScanRoots()
            self.libraryScanStatus = "Removed \(root.standardizedURL.lastPathComponent)"
        }
        libraryOperations.installTask(task, generation: generation)
    }

    func hasLibraryScanLog(_ id: Int64) -> Bool {
        libraryScanController?.hasLog(rootID: id) ?? false
    }

    func openLibraryScanLog(_ id: Int64) {
        libraryScanController?.showLog(rootID: id)
    }

    func canMoveLibraryScanRootUp(_ id: Int64) -> Bool {
        guard let index = libraryScanRoots.firstIndex(where: { $0.id == id }) else { return false }
        return index > 0
    }

    func canMoveLibraryScanRootDown(_ id: Int64) -> Bool {
        guard let index = libraryScanRoots.firstIndex(where: { $0.id == id }) else { return false }
        return index < libraryScanRoots.index(before: libraryScanRoots.endIndex)
    }

    func moveLibraryScanRootUp(_ id: Int64) {
        guard let index = libraryScanRoots.firstIndex(where: { $0.id == id }), index > 0 else { return }
        libraryScanRoots.swapAt(index - 1, index)
        persistLibraryScanRootOrder()
    }

    func moveLibraryScanRootDown(_ id: Int64) {
        guard let index = libraryScanRoots.firstIndex(where: { $0.id == id }),
              index < libraryScanRoots.index(before: libraryScanRoots.endIndex) else { return }
        libraryScanRoots.swapAt(index, index + 1)
        persistLibraryScanRootOrder()
    }

    func rescanLibraryRoot(_ id: Int64) {
        guard let root = libraryScanRoots.first(where: { $0.id == id }) else { return }
        runModernLibraryScan(for: [root], mode: requestedLibraryScanMode)
    }

    func scanLibraryRoot(_ id: Int64) {
        guard let root = libraryScanRoots.first(where: { $0.id == id }) else { return }
        runModernLibraryScan(for: [root], mode: requestedLibraryScanMode)
    }

    func trimMissingLibrary() {
        guard !libraryScanInProgress,
              let databaseURL = libraryDatabase?.databaseURL else { return }
        let generation = libraryOperations.beginTask()
        libraryScanInProgress = true
        trimMissingProgress = LibraryScanProgress(current: 0, total: 0)
        trimMissingCurrentPath = nil
        libraryScanStatus = "Test Links • preparing…"

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.libraryOperations.isCurrentTask(generation) {
                    self.libraryScanInProgress = false
                    self.trimMissingProgress = nil
                    self.trimMissingCurrentPath = nil
                    self.libraryOperations.finishTask(generation: generation)
                }
            }
            await Task.yield()
            let sources = await Task.detached(priority: .utility) {
                try? LibraryDatabase(databaseURL: databaseURL).indexedSources()
            }.value
            guard let sources else {
                guard self.libraryOperations.isCurrentTask(generation) else { return }
                self.libraryScanStatus = "Test Links failed to read the library."
                return
            }
            guard self.libraryOperations.isCurrentTask(generation), !Task.isCancelled else { return }
            self.trimMissingProgress = LibraryScanProgress(current: 0, total: sources.count)
            self.libraryScanStatus = "Test Links • checking \(sources.count) sources…"
            let integrityTask = Task.detached(priority: .utility) {
                await LibraryIntegrityChecker.check(
                    sources: sources,
                    progress: { current, total, path in
                        Task { @MainActor [weak self] in
                            guard let self, self.libraryOperations.isCurrentTask(generation) else { return }
                            self.trimMissingProgress = LibraryScanProgress(current: current, total: total)
                            self.trimMissingCurrentPath = path
                            self.libraryScanStatus = "Test Links • \(current) of \(total) sources checked"
                        }
                    }
                )
            }
            let result = await withTaskCancellationHandler {
                await integrityTask.value
            } onCancel: {
                integrityTask.cancel()
            }
            guard self.libraryOperations.isCurrentTask(generation), !Task.isCancelled else { return }
            let writeError = await Task.detached(priority: .utility) { () -> String? in
                do {
                    let database = try LibraryDatabase(databaseURL: databaseURL)
                    try database.markSourcesDead(result.missingSources)
                    try database.refreshDirtySidebarBuckets()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            guard self.libraryOperations.isCurrentTask(generation), !Task.isCancelled else { return }
            if let writeError {
                self.libraryScanStatus = "Integrity check failed: \(writeError)"
                return
            }
            self.trimmedLibraryScanRootIDs.formUnion(result.missingSources.map(\.rootID))
            self.persistTrimmedLibraryRootIDs()
            self.reloadLibraryScanRoots()
            self.reloadDatabaseSidebar()
            self.refreshDeadLinkSummary()
            self.libraryScanStatus = "Test Links • \(result.checkedCount) sources checked • \(result.missingSources.count) unlinked sources found"
        }
        libraryOperations.installTask(task, generation: generation)
    }

    func rescanEnabledLibraryRoots() {
        runModernLibraryScan(for: libraryScanRoots.filter(\.isEnabled), mode: requestedLibraryScanMode)
    }

    func purgeLibraryDatabase() {
        guard !libraryScanInProgress, let libraryDatabase else { return }
        do {
            try libraryDatabase.purgeIndexedLibrary()
            for root in libraryScanRoots {
                LibraryScanLogStore.remove(rootID: root.id)
            }
            trimmedLibraryScanRootIDs.removeAll()
            persistTrimmedLibraryRootIDs()
            reloadLibraryScanRoots()
            reloadDatabaseSidebar()
            resetSidebarContext(message: "Database reset")
            refreshDeadLinkSummary()
            libraryScanStatus = "Database reset"
        } catch {
            libraryScanStatus = "Could not reset database: \(error.localizedDescription)"
        }
    }

    func resetLibraryPaths() {
        guard !libraryScanInProgress,
              !libraryScanRoots.isEmpty,
              let databaseURL = libraryDatabase?.databaseURL else { return }
        let rootIDs = libraryScanRoots.map(\.id)
        let generation = libraryOperations.beginTask()
        libraryScanInProgress = true
        libraryScanStatus = "Removing library paths…"

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.libraryOperations.isCurrentTask(generation) {
                    self.libraryScanInProgress = false
                    self.libraryOperations.finishTask(generation: generation)
                }
            }
            await Task.yield()
            let errorDescription = await Task.detached(priority: .utility) { () -> String? in
                do {
                    try LibraryDatabase(databaseURL: databaseURL).detachAttachedRoots()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            guard self.libraryOperations.isCurrentTask(generation), !Task.isCancelled else { return }
            if let errorDescription {
                self.libraryScanStatus = "Could not reset library paths: \(errorDescription)"
                return
            }
            for rootID in rootIDs {
                self.libraryScanController?.closeLiveLog(rootID: rootID)
            }
            self.reloadLibraryScanRoots()
            self.clearLibraryState()
            self.libraryScanStatus = "Library paths reset"
        }
        libraryOperations.installTask(task, generation: generation)
    }

    func stopLibraryScan() {
        if trimMissingProgress != nil {
            libraryOperations.cancelActiveTask()
            libraryScanInProgress = false
            trimMissingProgress = nil
            trimMissingCurrentPath = nil
            libraryScanStatus = "Test Links stopped"
            return
        }
        libraryScanController?.stop()
    }

    private var requestedLibraryScanMode: ScanMode {
        forceLibraryScan ? .newScan : .incremental
    }

    var queuedLibraryScanCount: Int { libraryScanController?.queuedRequestCount ?? 0 }

    var libraryOperationProgress: LibraryScanProgress? {
        libraryOperations.operationProgress
    }

    var libraryOperationIsLinkTest: Bool {
        trimMissingProgress != nil
    }

    private func runModernLibraryScan(for roots: [LibraryScanRoot], mode: ScanMode) {
        guard !roots.isEmpty else { return }
        guard let libraryScanController else {
            libraryScanStatus = "Library database unavailable."
            return
        }
        libraryScanController.scan(roots: roots, mode: mode)
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
        selectedDatabaseGameID = item.id
        selectedDatabaseGameIDs = [item.id]
        statusText = DatabaseSidebarPresentation.selectionStatusText(for: item)
    }

    func selectDatabaseGames(ids: [String], primaryID: String?) {
        selectedDatabaseGameIDs = Set(ids)
        selectedDatabaseGameID = primaryID
        let selectedItems = databaseGameItems.filter { selectedDatabaseGameIDs.contains($0.id) }
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
                    request: request
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
                metadataInspectionPolicy: .databaseSnapshot,
                autoplay: autoplay
            )
            let applyElapsed = applyStartedAt.duration(to: .now)
            Self.playlistLoadLogger.info(
                "sidebar queue applied: \(loaded.tracks.count) tracks in \(String(describing: applyElapsed), privacy: .public)"
            )
            self.statusText = replace
                ? "Queued \(loaded.tracks.count) tracks from \(label)"
                : "Enqueued \(loaded.tracks.count) tracks from \(label)"
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
        metadataInspectionPolicy: PlaylistMetadataInspectionPolicy = .inspectMissing,
        autoplay: Bool = false
    ) {
        guard !tracks.isEmpty else {
            statusText = "No supported tracks in \(folderURL.lastPathComponent)"
            return
        }

        metadataCache = seedMetadataCache
        playlistMetadataInspectionPolicy = metadataInspectionPolicy
        playlistColumnWidthHints = widthHints

        if replace {
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
            }
            playlist = Self.deduplicatedTracks(tracks)
            syncManualPlaylistOrder()
            reapplyPlaylistSortIfNeeded()
            if let currentTrack,
               playlist.contains(where: { $0.id == currentTrack.id }) {
                selectedTrackID = currentTrack.id
            } else {
                selectedTrackID = playlist.first?.id
            }
            selectedTrackIDs = selectedTrackID.map { [$0] } ?? []
        } else {
            appendTracksToPlaylist(
                tracks,
                status: "Queued \(tracks.count) tracks from \(folderURL.lastPathComponent)",
                seedMetadataCache: seedMetadataCache,
                widthHints: widthHints,
                metadataInspectionPolicy: metadataInspectionPolicy
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
        widthHints: PlaylistColumnWidthHints? = nil,
        metadataInspectionPolicy: PlaylistMetadataInspectionPolicy = .inspectMissing
    ) {
        var existing = Set(playlist.map(\.id))
        let uniqueTracks = tracks.filter { existing.insert($0.id).inserted }
        guard !uniqueTracks.isEmpty else {
            statusText = status
            return
        }
        metadataCache.merge(seedMetadataCache) { current, _ in current }
        if metadataInspectionPolicy == .databaseSnapshot {
            playlistMetadataInspectionPolicy = .databaseSnapshot
        }
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

    var canExportSelectedTracksToAAC: Bool {
        !orderedSelectedPlaylistTracks().isEmpty && audioExportTask == nil
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

    func exportSelectedTracksToAAC() {
        exportTracksToAAC(orderedSelectedPlaylistTracks())
    }

    func savePreferencesNow() {
        AppSessionPersistence.savePlaybackPreferences(
            longPlayEnabled: longPlayEnabled,
            playlistFollowsCursor: playlistFollowsCursor,
            manualPreFadeSeconds: manualPreFadeSeconds,
            endFadeEnabled: endFadeEnabled,
            fadedSkipEnabled: fadedSkipEnabled,
            spectrumGradientStartColor: spectrumGradientStartColor,
            spectrumGradientEndColor: spectrumGradientEndColor,
            spectrumPeakColor: spectrumPeakColor,
            spectrumEnabled: spectrumEnabled,
            spectrumBandCount: spectrumBandCount,
            equalizerEnabled: equalizerEnabled,
            equalizerBandGains: equalizerBandGains,
            appVolume: appVolume,
            monoEnabled: monoEnabled,
            randomPlaybackScopeRawValue: randomPlaybackScope.rawValue,
            repeatModeRawValue: repeatMode.rawValue,
            sidebarDoubleClickActionRawValue: sidebarDoubleClickAction.rawValue,
            lastAudioExportDirectoryPath: lastAudioExportDirectoryURL?.path,
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
            sidebarBrowserModeRawValue: sidebarBrowserMode.rawValue
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

    func setAppVolume(_ volume: Float) {
        appVolume = AudioOutputVolume.clamped(volume)
        savePreferencesNow()
    }

    func setMonoEnabled(_ enabled: Bool) {
        monoEnabled = enabled
        savePreferencesNow()
    }

    func setSpectrumBandCount(_ bandCount: Int) {
        spectrumBandCount = SpectrumBandCount.clamped(bandCount)
        savePreferencesNow()
    }

    func resetSpectrumColors() {
        spectrumGradientStartColor = Self.defaultSpectrumGradientStartColor
        spectrumGradientEndColor = Self.defaultSpectrumGradientEndColor
        spectrumPeakColor = Self.defaultSpectrumPeakColor
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
        expandedDatabaseSystems = enabled && effectiveSidebarBrowserMode == .games && !sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Set(visibleDatabaseGameItems.map { sidebarSystemName(for: $0) })
            : []
        savePreferencesNow()
    }

    func setPreferEmbeddedConsoleTags(_ enabled: Bool) {
        guard !libraryScanInProgress,
              preferEmbeddedConsoleTags != enabled,
              let databaseURL = libraryDatabase?.databaseURL else { return }
        let previous = preferEmbeddedConsoleTags
        let generation = libraryOperations.beginTask()
        libraryScanInProgress = true
        preferEmbeddedConsoleTags = enabled
        libraryDatabase?.preferEmbeddedConsoleTags = enabled
        savePreferencesNow()
        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.libraryOperations.isCurrentTask(generation) {
                    self.libraryScanInProgress = false
                    self.libraryOperations.finishTask(generation: generation)
                }
            }
            let errorDescription = await Task.detached(priority: .utility) {
                do {
                    let database = try LibraryDatabase(databaseURL: databaseURL, preferEmbeddedConsoleTags: enabled)
                    try database.rewriteSidebarIdentity(preferEmbeddedMetadata: enabled)
                    return nil as String?
                } catch {
                    return error.localizedDescription
                }
            }.value
            guard self.libraryOperations.isCurrentTask(generation), !Task.isCancelled else { return }
            if let errorDescription {
                self.preferEmbeddedConsoleTags = previous
                self.libraryDatabase?.preferEmbeddedConsoleTags = previous
                self.savePreferencesNow()
                self.libraryScanStatus = "Could not update console grouping: \(errorDescription)"
                return
            }
            self.libraryScanStatus = enabled
                ? "Database console grouping now prefers embedded tags."
                : "Database console grouping now prefers collection tags and folders."
            self.reloadDatabaseSidebar()
        }
    }

    func setSidebarBrowserMode(_ mode: SidebarBrowserMode) {
        sidebarBrowserMode = mode
        applySidebarSearch()
        loadDatabaseSidebarIfNeeded()
        savePreferencesNow()
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
        guard !isClearingArchiveCache, !libraryScanInProgress else { return }
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

    func refreshDeadLinkSummary() {
        guard !isDeletingDeadLinks else { return }
        let generation = deadLinkSummaryTaskOwner.begin()
        let databaseURL = libraryDatabase?.databaseURL
        let task = Task { @MainActor [weak self] in
            let summary = await Task.detached(priority: .utility) {
                databaseURL.flatMap { try? LibraryDatabaseMaintenance.summary(databaseURL: $0) }
            }.value
            guard let self,
                  !Task.isCancelled,
                  self.deadLinkSummaryTaskOwner.isCurrent(generation) else { return }
            self.applyDeadLinkSummary(summary)
            self.deadLinkSummaryTaskOwner.finish(generation: generation)
        }
        deadLinkSummaryTaskOwner.install(task, generation: generation)
    }

    func deleteDeadLinks() {
        guard !isDeletingDeadLinks,
              !libraryScanInProgress,
              let databaseURL = libraryDatabase?.databaseURL else { return }
        isDeletingDeadLinks = true
        deadLinkSummaryTaskOwner.cancel()
        deadLinkCleanupTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try LibraryDatabaseMaintenance.clearDeadLinks(databaseURL: databaseURL) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.isDeletingDeadLinks = false
            self.deadLinkCleanupTask = nil
            switch result {
            case .success(let clearedCount):
                self.reloadLibraryScanRoots()
                self.reloadDatabaseSidebar()
                self.refreshDeadLinkSummary()
                self.libraryScanStatus = clearedCount == 1
                    ? "Database cleanup • 1 unlinked source cleared"
                    : "Database cleanup • \(clearedCount) unlinked sources cleared"
            case .failure(let error):
                self.libraryScanStatus = "Clean Unlinked failed: \(error.localizedDescription)"
            }
        }
    }

    private func applyDeadLinkSummary(_ summary: LibraryDatabaseMaintenanceSummary?) {
        guard let summary else {
            deadLinkCount = 0
            databaseEntryCount = 0
            unlinkedDatabaseEntryCount = 0
            deadLinkSummaryText = "Unavailable"
            return
        }
        deadLinkCount = summary.deadLinkCount
        databaseEntryCount = summary.indexedTrackCount
        unlinkedDatabaseEntryCount = summary.unlinkedTrackCount
        deadLinkSummaryText = summary.deadLinkSummaryText
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
        if expandedDatabaseSystems.contains(systemName) {
            expandedDatabaseSystems.remove(systemName)
        } else {
            expandedDatabaseSystems.insert(systemName)
        }
    }

    func sidebarSystemName(for item: DatabaseGameItem) -> String {
        item.systemName.isEmpty ? "Unknown System" : item.systemName
    }

    func exportTracksToAAC(_ tracks: [TrackItem]) {
        guard audioExportTask == nil else {
            audioExportWindowController?.showWindow(nil)
            return
        }

        let deduplicatedTracks = Array(NSOrderedSet(array: tracks)) as? [TrackItem] ?? []
        guard !deduplicatedTracks.isEmpty else { return }

        let defaultDirectory = lastAudioExportDirectoryURL ?? deduplicatedTracks[0].revealURL.deletingLastPathComponent()
        let panel = AudioExportAACService.makeDestinationFolderPanel(defaultDirectory: defaultDirectory)
        guard panel.runModal() == .OK, let outputDirectory = panel.urls.first?.standardizedFileURL else { return }
        lastAudioExportDirectoryURL = outputDirectory

        let metadataSnapshot = metadataCache
        let longPlaySetting = longPlayEnabled
        let manualPreFadeSetting = manualPreFadeSeconds
        let fadeSetting = fadeSeconds

        let windowController = ensureAudioExportWindowController()
        let preparingSnapshot = AudioExportProgressSnapshot(
            phase: .preparing,
            title: "Preparing AAC export",
            outputDirectoryPath: outputDirectory.path,
            currentFileName: nil,
            completedFiles: 0,
            totalFiles: deduplicatedTracks.count,
            currentFileProgress: nil,
            batchProgress: 0
        )
        audioExportProgressSnapshot = preparingSnapshot
        windowController.present(snapshot: preparingSnapshot)
        statusText = "Preparing AAC export…"

        audioExportTask = Task { [weak self] in
            guard let self else { return }

            do {
                let requests = try await AudioExportAACService.buildRequests(
                    tracks: deduplicatedTracks,
                    cachedMetadata: metadataSnapshot,
                    outputDirectory: outputDirectory,
                    longPlayEnabled: longPlaySetting,
                    manualPreFadeSeconds: manualPreFadeSetting,
                    fadeSeconds: fadeSetting
                )

                let resolvedMetadata = Dictionary(uniqueKeysWithValues: requests.map { ($0.track.id, $0.metadata) })
                await MainActor.run {
                    self.metadataCache.merge(resolvedMetadata) { current, _ in current }
                    self.playlistMetadataLoadToken += 1
                }

                let result = try await AudioExportAACService.export(requests: requests) { snapshot in
                    Task { @MainActor [weak self] in
                        self?.audioExportProgressSnapshot = snapshot
                        self?.audioExportWindowController?.apply(snapshot: snapshot)
                    }
                }

                await MainActor.run {
                    let snapshot = AudioExportProgressSnapshot(
                        phase: .completed,
                        title: "AAC export complete",
                        outputDirectoryPath: result.outputDirectory.path,
                        currentFileName: nil,
                        completedFiles: result.exportedCount,
                        totalFiles: result.exportedCount,
                        currentFileProgress: 1,
                        batchProgress: 1
                    )
                    self.audioExportProgressSnapshot = snapshot
                    self.audioExportWindowController?.apply(snapshot: snapshot)
                    self.audioExportWindowController?.closeAutomatically()
                    self.statusText = "Exported \(result.exportedCount) AAC file\(result.exportedCount == 1 ? "" : "s")"
                    self.audioExportTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    let previous = self.audioExportProgressSnapshot
                    let snapshot = AudioExportProgressSnapshot(
                        phase: .cancelled,
                        title: "AAC export cancelled",
                        outputDirectoryPath: outputDirectory.path,
                        currentFileName: previous?.currentFileName,
                        completedFiles: previous?.completedFiles ?? 0,
                        totalFiles: deduplicatedTracks.count,
                        currentFileProgress: previous?.currentFileProgress,
                        batchProgress: previous?.batchProgress ?? 0
                    )
                    self.audioExportProgressSnapshot = snapshot
                    self.audioExportWindowController?.apply(snapshot: snapshot)
                    self.audioExportWindowController?.closeAutomatically()
                    self.statusText = "AAC export cancelled"
                    self.audioExportTask = nil
                }
            } catch {
                await MainActor.run {
                    let previous = self.audioExportProgressSnapshot
                    let snapshot = AudioExportProgressSnapshot(
                        phase: .failed,
                        title: "AAC export failed",
                        outputDirectoryPath: outputDirectory.path,
                        currentFileName: previous?.currentFileName,
                        completedFiles: previous?.completedFiles ?? 0,
                        totalFiles: deduplicatedTracks.count,
                        currentFileProgress: previous?.currentFileProgress,
                        batchProgress: previous?.batchProgress ?? 0
                    )
                    self.audioExportProgressSnapshot = snapshot
                    self.audioExportWindowController?.apply(snapshot: snapshot)
                    self.audioExportWindowController?.closeAutomatically()
                    self.statusText = "AAC export failed"
                    self.audioExportTask = nil
                }
            }
        }
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
        guard let nextTrack = QueueTransportNavigation.adjacentTrack(
            from: transportNavigationAnchor,
            in: playlist,
            direction: .next,
            wraps: true
        ) else { return }
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
        let task = Task { [weak self] in
            let loaded: LoadedPlaylistData
            do {
                loaded = try await PlaylistQueueLoader.loadLibraryTracksForGames(
                    databaseURL: databaseURL,
                    gameItems: [item]
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
        guard let previousTrack = QueueTransportNavigation.adjacentTrack(
            from: transportNavigationAnchor,
            in: playlist,
            direction: .previous,
            wraps: true
        ) else { return }
        requestAdjacentPlayback(previousTrack)
    }

    private func requestAdjacentPlayback(_ track: TrackItem) {
        guard fadedSkipEnabled,
              isPlaying,
              fadeSeconds > 0,
              currentTrack != nil,
              playbackElapsedSeconds < Double(effectivePreFadeSeconds) else {
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
        let fadeDuration = TimeInterval(fadeSeconds)
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
                let metadata = try await playback.reconfigureCurrentTrack(plan: plan)
                let snapshot = await playback.statusSnapshot()
                self.currentMetadata = metadata
                self.updatePlaylistMetadata(for: currentTrack.id, metadata: metadata)
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
        cancelFadedSkip()
        let target = seekPreviewSeconds
        isSeeking = false
        let playback = self.playback
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
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
            let seedMetadata = if !isNewTrack, let currentMetadata {
                currentMetadata
            } else if let cachedMetadata {
                cachedMetadata
            } else {
                try await PlaybackInspection.inspectMetadata(track: track)
            }

            try Task.checkCancellation()
            guard playbackRequestState.isCurrent(generation) else { return }

            let plan = playbackPlan(for: seedMetadata, trackPathExtension: track.playablePathExtension)
            let loadedMetadata = try await playback.play(track: track, plan: plan, requestID: requestID)
            guard playbackRequestState.isCurrent(generation) else { return }
            currentTrack = track
            pendingPlaybackTrack = nil
            currentMetadata = loadedMetadata
            updatePlaylistMetadata(for: track.id, metadata: loadedMetadata)
            isPlaying = true
            didAutoAdvanceForCurrentTrack = false
            playbackElapsedSeconds = 0
            seekPreviewSeconds = 0

            let songTitle = loadedMetadata.song.isEmpty ? track.displayName : loadedMetadata.song
            let gameTitle = loadedMetadata.game.isEmpty ? track.groupDisplayName : loadedMetadata.game
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
            let seconds = milliseconds / 1_000
            playlistDurationSecondsByTrackID[track.id] = seconds
            playlistDurationTotalSeconds += seconds
        }
        updatePlaylistTotalDurationReadout()
    }

    private func updatePlaylistDuration(for trackID: TrackItem.ID, metadata: TrackMetadata) {
        guard playlistDurationTrackIDs.contains(trackID) else { return }
        let previous = playlistDurationSecondsByTrackID[trackID] ?? 0
        let updated = max(metadata.playLengthMs, 0) / 1_000
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

    func libraryScanRootStatusText(_ root: LibraryScanRoot) -> String {
        let order = (libraryScanRoots.firstIndex(where: { $0.id == root.id }) ?? 0) + 1
        return DatabaseSidebarPresentation.scanRootStatusText(root, order: order)
    }

    func libraryScanRootDetailText(_ root: LibraryScanRoot) -> String {
        if libraryScanProgressByRootID[root.id] != nil {
            return "Scanning"
        }
        if let error = root.lastScanError, !error.isEmpty {
            return error
        }
        if root.lastScanCompletedAt != nil,
           let tally = try? libraryDatabase?.scanResultTally(rootID: root.id) {
            return "\(tally.successful) / \(tally.total)"
        }
        return root.lastScanCompletedAt == nil ? "Ready to scan" : "—"
    }

    func libraryScanRootIsEmpty(_ root: LibraryScanRoot) -> Bool {
        root.lastScanCompletedAt != nil && root.lastScanTrackCount == 0
    }

    func libraryScanRootHasIssues(_ root: LibraryScanRoot) -> Bool {
        root.lastScanError?.isEmpty == false || LibraryScanLogStore.exists(rootID: root.id)
    }

    func libraryScanRootIsClean(_ root: LibraryScanRoot) -> Bool {
        cleanLibraryScanRootIDs.contains(root.id) && !libraryScanRootIsEmpty(root) && root.lastScanError == nil
    }

    func libraryScanRootNeedsRescan(_ root: LibraryScanRoot) -> Bool {
        trimmedLibraryScanRootIDs.contains(root.id)
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

    private var transportPlaybackTarget: TrackItem? {
        QueueTransportNavigation.transportPlaybackTarget(
            currentTrack: currentTrack,
            selectedTrackID: selectedTrackID,
            playlist: playlist
        )
    }

    private var transportNavigationAnchor: TrackItem? {
        pendingPlaybackTrack ?? currentTrack ?? transportPlaybackTarget
    }

    private func playbackPlan(for metadata: TrackMetadata?, trackPathExtension: String? = nil) -> PlaybackPlan {
        PlaybackTimingPolicy.playbackPlan(
            metadata: metadata ?? currentMetadata,
            trackPathExtension: trackPathExtension ?? currentTrack?.playablePathExtension,
            longPlayEnabled: longPlayEnabled,
            manualPreFadeSeconds: manualPreFadeSeconds,
            fadeSeconds: fadeSeconds
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
                if !snapshot.isPlaying {
                    self.toolbarSpectrum.setAnimating(false)
                }
                self.handlePlaybackCompletionIfNeeded()
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
              let currentTrack,
              !playlist.isEmpty else {
            return
        }

        // Only the drained native output may declare completion. Elapsed-time
        // thresholds can mistake a pause or a short/unknown duration for EOF.
        guard playbackReachedEnd else { return }

        didAutoAdvanceForCurrentTrack = true
        if repeatMode == .song {
            requestPlayback(for: currentTrack)
            return
        }
        if randomPlaybackScope == .library {
            playRandomLibraryTrackWhenReady()
            return
        }
        if randomPlaybackScope == .playlist, let randomTrack = randomPlaybackTarget() {
            requestPlayback(for: randomTrack)
            return
        }
        let nextTrack = QueueTransportNavigation.completionAdvanceTarget(
            currentTrack: currentTrack,
            playlist: playlist
        )
        guard let nextTrack else {
            guard repeatMode == .playlist, let firstTrack = playlist.first else { return }
            requestPlayback(for: firstTrack)
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
        return enabledLibraryRootURLs
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
                widthHints: loaded.widthHints,
                metadataInspectionPolicy: .databaseSnapshot
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
                widthHints: loaded.widthHints,
                metadataInspectionPolicy: .databaseSnapshot
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

    private func refreshPlaylistMetadata(limit: Int? = nil) {
        let generation = playlistMetadataTaskOwner.begin()
        let tracks = playlist
        let cachedMetadata = metadataCache

        guard !tracks.isEmpty else {
            playlistColumnWidthHints = nil
            playlistMetadataLoadToken += 1
            playlistMetadataTaskOwner.finish(generation: generation)
            return
        }

        // A sidebar playlist is a database projection. Selection is required
        // to remain strictly database-only: no decoder probes, archive
        // materialization, or filesystem metadata reads are permitted here.
        guard playlistMetadataInspectionPolicy == .inspectMissing else {
            if playlistColumnWidthHints == nil {
                playlistColumnWidthHints = Self.buildPlaylistColumnWidthHints(
                    tracks: tracks,
                    metadata: cachedMetadata
                )
            }
            playlistMetadataLoadToken += 1
            playlistMetadataTaskOwner.finish(generation: generation)
            return
        }

        let unresolvedTracks = tracks.filter { track in
            guard let metadata = cachedMetadata[track.id] else { return true }

            // Older database scans may have cached SPC tags but no duration.
            // Reinspect those rows so the playlist gets the libgme play length
            // without requiring selection or playback.
            if track.playablePathExtension == "spc" && metadata.playLengthMs <= 0 {
                return true
            }

            // Repair incomplete legacy archive rows after they enter a playlist.
            return track.isArchiveEntry
                && metadata.game.isEmpty
                && metadata.song.isEmpty
                && metadata.system.isEmpty
                && metadata.author.isEmpty
                && metadata.comment.isEmpty
                && metadata.introLengthMs == 0
                && metadata.loopLengthMs == 0
                && metadata.playLengthMs == 0
                && metadata.fadeLengthMs == 0
        }
        let missingTracks: [TrackItem]
        if let limit {
            missingTracks = Array(unresolvedTracks.prefix(limit))
        } else {
            missingTracks = unresolvedTracks
        }
        if missingTracks.isEmpty {
            if playlistColumnWidthHints == nil {
                playlistColumnWidthHints = Self.buildPlaylistColumnWidthHints(
                    tracks: tracks,
                    metadata: cachedMetadata
                )
            }
            playlistMetadataLoadToken += 1
            playlistMetadataTaskOwner.finish(generation: generation)
            return
        }

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var resolvedMetadata = cachedMetadata
            let jobs = PlaybackInspection.prepareMetadataInspectionJobs(
                tracks: missingTracks
            )
            await withTaskGroup(of: (String, TrackMetadata?).self) { group in
                var nextJobIndex = 0
                var pendingMetadata: [String: TrackMetadata] = [:]
                let initialJobCount = min(
                    PlaybackInspection.metadataWorkerLimit,
                    jobs.count
                )
                for _ in 0..<initialJobCount {
                    let job = jobs[nextJobIndex]
                    nextJobIndex += 1
                    group.addTask {
                        let metadata = try? await PlaybackInspection.inspectMetadata(
                            track: job.track,
                            fileURL: job.fileURL
                        )
                        return (job.track.id, metadata)
                    }
                }

                while let (trackID, metadata) = await group.next() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }

                    if let metadata {
                        resolvedMetadata[trackID] = metadata
                        pendingMetadata[trackID] = metadata
                        if pendingMetadata.count >= 64 {
                            let batch = pendingMetadata
                            pendingMetadata.removeAll(keepingCapacity: true)
                            await MainActor.run {
                                guard self.playlistMetadataTaskOwner.isCurrent(generation) else { return }
                                self.updatePlaylistMetadata(batch)
                            }
                        }
                    }

                    if nextJobIndex < jobs.count {
                        let job = jobs[nextJobIndex]
                        nextJobIndex += 1
                        group.addTask {
                            let metadata = try? await PlaybackInspection.inspectMetadata(
                                track: job.track,
                                fileURL: job.fileURL
                            )
                            return (job.track.id, metadata)
                        }
                    }
                }

                if !pendingMetadata.isEmpty, !Task.isCancelled {
                    await MainActor.run {
                        guard self.playlistMetadataTaskOwner.isCurrent(generation) else { return }
                        self.updatePlaylistMetadata(pendingMetadata)
                    }
                }
            }

            let widthHints = Self.buildPlaylistColumnWidthHints(
                tracks: tracks,
                metadata: resolvedMetadata
            )

            await MainActor.run {
                guard self.playlistMetadataTaskOwner.isCurrent(generation) else { return }
                self.playlistColumnWidthHints = widthHints
                if self.playlistSortDependsOnMetadata(self.playlistSortColumn),
                   let sortColumn = self.playlistSortColumn {
                    self.applyPlaylistSort(
                        column: sortColumn,
                        direction: self.playlistSortDirection,
                        updateStatus: false
                    )
                }
                self.playlistMetadataLoadToken += 1
                self.playlistMetadataTaskOwner.finish(generation: generation)
            }
        }
        playlistMetadataTaskOwner.install(task, generation: generation)
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

    private static func deduplicatedTracks(_ tracks: [TrackItem]) -> [TrackItem] {
        var seen = Set<TrackItem.ID>()
        return tracks.filter { seen.insert($0.id).inserted }
    }

    private func reloadLibraryScanRoots() {
        guard let libraryDatabase else { return }
        do {
            libraryScanRoots = try libraryDatabase.loadRoots()
            cleanLibraryScanRootIDs = Set(libraryScanRoots.compactMap { root in
                root.lastScanCompletedAt != nil && root.lastScanTrackCount > 0 && !LibraryScanLogStore.exists(rootID: root.id) ? root.id : nil
            })
            trimmedLibraryScanRootIDs.formIntersection(Set(libraryScanRoots.map(\.id)))
            persistTrimmedLibraryRootIDs()
        } catch {
            libraryScanStatus = "Could not load scan roots: \(error.localizedDescription)"
        }
    }

    /// Checkbox changes stay local until input settles. Rebuilding the Games
    /// sidebar for every individual root made a simple sequence of checks
    /// feel like a library recalculation and blocked further interaction.
    private func persistLibraryRootEnabledStatesAfterInteraction() {
        guard let databaseURL = libraryDatabase?.databaseURL else { return }
        let enabledStates = Dictionary(
            uniqueKeysWithValues: libraryScanRoots.map { ($0.id, $0.isEnabled) }
        )
        let generation = libraryRootEnableTaskOwner.begin()
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled,
                  let self,
                  self.libraryRootEnableTaskOwner.isCurrent(generation) else {
                return
            }

            let errorDescription = await Task.detached(priority: .utility) { () -> String? in
                do {
                    try LibraryDatabase(databaseURL: databaseURL).setRootEnabledStates(enabledStates)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value

            guard !Task.isCancelled,
                  self.libraryRootEnableTaskOwner.isCurrent(generation) else {
                return
            }
            if let errorDescription {
                self.libraryScanStatus = "Could not update path state: \(errorDescription)"
                self.reloadLibraryScanRoots()
                self.libraryRootEnableTaskOwner.finish(generation: generation)
                return
            }

            self.reloadLibraryScanRoots()
            self.reloadDatabaseSidebar()
            self.syncActiveRootToLibraryScanRoots()
            self.libraryRootEnableTaskOwner.finish(generation: generation)
        }
        libraryRootEnableTaskOwner.install(task, generation: generation)
    }

    private func reloadDatabaseSidebar() {
        databaseSidebarLoader.invalidateAndLoad(
            databaseURL: libraryDatabase?.databaseURL,
            mode: effectiveSidebarBrowserMode,
            didLoadGames: { [weak self] in self?.databaseGamesDidLoad() },
            didLoadFiles: { [weak self] in self?.databaseFilesDidLoad() }
        )
    }

    private func loadDatabaseSidebarIfNeeded() {
        databaseSidebarLoader.loadIfNeeded(
            databaseURL: libraryDatabase?.databaseURL,
            mode: effectiveSidebarBrowserMode,
            didLoadGames: { [weak self] in self?.databaseGamesDidLoad() },
            didLoadFiles: { [weak self] in self?.databaseFilesDidLoad() }
        )
    }

    private func databaseGamesDidLoad() {
        if sidebarSystemMode,
           !sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            expandedDatabaseSystems = Set(visibleDatabaseGameItems.map { sidebarSystemName(for: $0) })
        }
        if randomPlaybackScope == .library {
            randomLibraryTracks = []
            randomLibraryLoadTaskOwner.cancel()
            loadRandomLibraryTracks()
        }
    }

    private func databaseFilesDidLoad() {
        applyDatabaseFileSidebarSearch()
    }

    private func persistLibraryScanRootOrder() {
        try? libraryDatabase?.updateRootOrder(idsInOrder: libraryScanRoots.map(\.id))
        reloadLibraryScanRoots()
        syncActiveRootToLibraryScanRoots()
    }

    private func persistTrimmedLibraryRootIDs() {
        UserDefaults.standard.set(trimmedLibraryScanRootIDs.map { NSNumber(value: $0) }, forKey: "trimmedLibraryScanRootIDs")
    }

    private func syncActiveRootToLibraryScanRoots(preferredRoot: URL? = nil) {
        let enabledRoots = libraryScanRoots.filter(\.isEnabled)

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
        endFadeEnabled = preferences.endFadeEnabled
        fadedSkipEnabled = preferences.fadedSkipEnabled
        if let storedStartColor = preferences.spectrumGradientStartColor.flatMap(AppSessionPersistence.deserializeColor) {
            spectrumGradientStartColor = storedStartColor
        }
        if let storedEndColor = preferences.spectrumGradientEndColor.flatMap(AppSessionPersistence.deserializeColor) {
            spectrumGradientEndColor = storedEndColor
        }
        if let storedPeakColor = preferences.spectrumPeakColor.flatMap(AppSessionPersistence.deserializeColor) {
            spectrumPeakColor = storedPeakColor
        }
        spectrumEnabled = preferences.spectrumEnabled
        spectrumBandCount = preferences.spectrumBandCount
        equalizerEnabled = preferences.equalizerEnabled
        if let storedGains = preferences.equalizerBandGains,
           storedGains.count == AudioEqualizer.bandFrequencies.count {
            equalizerBandGains = storedGains.map { AudioEqualizer.clampedGain(Float($0)) }
        }
        appVolume = AudioOutputVolume.clamped(Float(preferences.appVolume))
        monoEnabled = preferences.monoEnabled
        randomPlaybackScope = RandomPlaybackScope(rawValue: preferences.randomPlaybackScopeRawValue ?? "off") ?? .off
        repeatMode = RepeatMode(rawValue: preferences.repeatModeRawValue ?? "off") ?? .off
        if randomPlaybackScope == .library { loadRandomLibraryTracks() }
        if let storedAction = preferences.sidebarDoubleClickActionRawValue.flatMap(SidebarDoubleClickAction.init(rawValue:)) {
            sidebarDoubleClickAction = storedAction
        }
        if let lastAudioExportDirectoryPath = preferences.lastAudioExportDirectoryPath {
            lastAudioExportDirectoryURL = URL(fileURLWithPath: lastAudioExportDirectoryPath, isDirectory: true).standardizedFileURL
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
            expandedDatabaseSystems = Set(visibleDatabaseGameItems.map { sidebarSystemName(for: $0) })
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
        let hasQuery = !sidebarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasQuery || sidebarBrowserMode == .games {
            databaseFileSidebarSearchTaskOwner.cancel()
            databaseSidebar.searchText = sidebarSearchQuery
            if sidebarSystemMode {
                expandedDatabaseSystems = hasQuery
                    ? Set(visibleDatabaseGameItems.map { sidebarSystemName(for: $0) })
                    : []
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

    private func ensureAudioExportWindowController() -> AudioExportProgressWindowController {
        if let audioExportWindowController {
            return audioExportWindowController
        }
        let controller = AudioExportProgressWindowController { [weak self] in
            self?.audioExportTask?.cancel()
            self?.statusText = "Cancelling AAC export…"
        }
        audioExportWindowController = controller
        return controller
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

    var isLibraryScanInProgress: Bool {
        libraryScanInProgress
    }

    func libraryScanProgressFraction(for rootID: Int64) -> Double? {
        libraryScanProgressByRootID[rootID]?.fraction
    }

    func libraryScanIsPreparing(rootID: Int64) -> Bool {
        libraryScanProgressByRootID[rootID]?.total == 0
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
        toolbarSpectrum.reset()
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

        let enabledRoots = libraryScanRoots.filter(\.isEnabled)
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
        let roots = libraryScanRoots
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
