import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class PlayerViewModel {
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

    var libraryScanRoots: [LibraryScanRoot] = []
    var sidebarDoubleClickAction: SidebarDoubleClickAction = .playNow
    var rootURL: URL?
    var selectedFolderPath: String?
    var librarySelectedFolderPath: String?
    var sidebarSearchText: String = "" {
        didSet {
            handleSidebarSearchChanged()
        }
    }
    var databaseSidebarFontSize: CGFloat = 12
    var databaseSidebarTextColor: DatabaseSidebarTextColor = .primary
    var playlistSearchText: String = "" {
        didSet {
            scheduleVisiblePlaylistRefresh()
        }
    }
    var databaseGameItems: [DatabaseGameItem] = []
    var visibleDatabaseGameItems: [DatabaseGameItem] = []
    var selectedDatabaseGameID: String?
    var selectedDatabaseGameIDs: Set<String> = []
    var browsedFolderTracks: [TrackItem] = []
    var selectedTrackID: TrackItem.ID?
    var selectedTrackIDs: Set<TrackItem.ID> = []
    var playlist: [TrackItem] = [] {
        didSet {
            scheduleVisiblePlaylistRefresh()
        }
    }
    var metadataCache: [String: TrackMetadata] = [:] {
        didSet {
            if !playlistSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scheduleVisiblePlaylistRefresh()
            }
        }
    }
    var visiblePlaylistItems: [TrackItem] = []
    var playlistColumnWidthHints: PlaylistColumnWidthHints?
    var playlistSortColumn: PlaylistSortColumn?
    var playlistSortDirection: PlaylistSortDirection = .ascending
    var currentTrack: TrackItem?
    var currentMetadata: TrackMetadata?
    let toolbarSpectrum = ToolbarSpectrumModel()
    var spectrumGradientStartColor = NSColor(
        calibratedRed: 0.000000,
        green: 0.976805,
        blue: 0.000000,
        alpha: 1.000000
    ) {
        didSet { toolbarSpectrum.gradientStartColor = spectrumGradientStartColor }
    }
    var spectrumGradientEndColor = NSColor(
        calibratedRed: 0.016804,
        green: 0.198351,
        blue: 1.000000,
        alpha: 1.000000
    ) {
        didSet { toolbarSpectrum.gradientEndColor = spectrumGradientEndColor }
    }
    var spectrumPeakColor = NSColor(
        calibratedRed: 1.000000,
        green: 0.149131,
        blue: 0.000000,
        alpha: 1.000000
    ) {
        didSet { toolbarSpectrum.peakColor = spectrumPeakColor }
    }
    var playlistFollowsCursor = false
    var longPlayEnabled = false
    var manualPreFadeSeconds: Int = 180
    var fadeSeconds: Int = 6
    var statusText: String = "Choose a music folder to begin."
    var isLoading = false
    var isPlaying = false
    var playbackElapsedSeconds: TimeInterval = 0
    var isSeeking = false
    var seekPreviewSeconds: Double = 0
    var playlistMetadataLoadToken = 0
    var libraryScanStatus: String?
    private(set) var cleanLibraryScanRootIDs: Set<Int64> = []
    private(set) var trimmedLibraryScanRootIDs: Set<Int64> = []
    private(set) var libraryScanInProgress = false

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
    @ObservationIgnored private var lastAudioExportDirectoryURL: URL?
    private var remoteTransportConfigured = false
    private let libraryDatabase: LibraryDatabase?
    private var playbackTimer: Timer?
    private var playlistLoadTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var libraryScanTask: Task<Void, Never>?
    private var scanLogWindows: [Int64: NSWindow] = [:]
    private var libraryScanProgressWindow: LibraryScanProgressWindowController?
    private var libraryScanGeneration = 0
    private var folderSelectionTask: Task<Void, Never>?
    private var queueBuildTask: Task<Void, Never>?
    private var visiblePlaylistTask: Task<Void, Never>?
    private var audioExportTask: Task<Void, Never>?
    private var playlistLoadGeneration = 0
    private var playbackRequestGeneration = 0
    private var folderSelectionGeneration = 0
    private var queueBuildGeneration = 0
    private var visiblePlaylistGeneration = 0
    private var didAutoAdvanceForCurrentTrack = false
    private var pendingPlaybackTrack: TrackItem?
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
        playback.setPlaybackStateHandler { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isSeeking {
                    self.playbackElapsedSeconds = snapshot.elapsedSeconds
                }
                self.isPlaying = snapshot.isPlaying
                if !snapshot.isPlaying {
                    self.toolbarSpectrum.reset()
                }
                self.updateRemoteTransportState()
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

    init() {
        AppSessionPersistence.migrateLegacyPreferences()
        do {
            libraryDatabase = try LibraryDatabase()
        } catch {
            libraryDatabase = nil
            libraryScanStatus = "Library database unavailable: \(error.localizedDescription)"
        }
        trimmedLibraryScanRootIDs = Set(
            UserDefaults.standard.array(forKey: "trimmedLibraryScanRootIDs")?.compactMap { ($0 as? NSNumber)?.int64Value } ?? []
        )
        toolbarSpectrum.gradientStartColor = spectrumGradientStartColor
        toolbarSpectrum.gradientEndColor = spectrumGradientEndColor
        toolbarSpectrum.peakColor = spectrumPeakColor
        restorePlaybackPreferences()
        reloadLibraryScanRoots()
        reloadDatabaseGameItems()
        restorePersistedPlaylist()
        restorePlaylistColumnState()
        sidebarSearchText = AppSessionPersistence.lastSidebarSearchText()
        playlistSearchText = AppSessionPersistence.lastPlaylistSearchText()
        startPlaybackTimer()
        restoreInitialSidebarMode()
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

        let addedPaths = panel.urls.map(\.standardizedFileURL.path)
        do {
            for url in panel.urls.map(\.standardizedFileURL) {
                try libraryDatabase.addRoot(path: url.path)
            }
        } catch {
            libraryScanStatus = "Could not save scan root: \(error.localizedDescription)"
            reloadLibraryScanRoots()
            return
        }
        reloadLibraryScanRoots()
        reloadDatabaseGameItems()
        syncActiveRootToLibraryScanRoots(preferredRoot: panel.urls.first?.standardizedFileURL)
        let addedRoots = libraryScanRoots.filter { addedPaths.contains($0.standardizedURL.path) && $0.isEnabled }
        runModernLibraryScan(for: addedRoots, mode: .newScan)
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

    func setLibraryScanRootEnabled(_ id: Int64, isEnabled: Bool) {
        try? libraryDatabase?.setRootEnabled(id: id, isEnabled: isEnabled)
        reloadLibraryScanRoots()
        reloadDatabaseGameItems()
        syncActiveRootToLibraryScanRoots()
    }

    func removeLibraryScanRoot(_ id: Int64) {
        try? libraryDatabase?.deleteRoot(id: id)
        LibraryScanLogStore.remove(rootID: id)
        scanLogWindows[id]?.close()
        scanLogWindows[id] = nil
        reloadLibraryScanRoots()
        reloadDatabaseGameItems()
        syncActiveRootToLibraryScanRoots()
    }

    func hasLibraryScanLog(_ id: Int64) -> Bool {
        LibraryScanLogStore.exists(rootID: id)
    }

    func openLibraryScanLog(_ id: Int64) {
        guard let root = libraryScanRoots.first(where: { $0.id == id }),
              let contents = try? String(
                contentsOf: LibraryScanLogStore.fileURL(rootID: id),
                encoding: .utf8
              ) else {
            return
        }

        if let window = scanLogWindows[id] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.string = contents
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.frame = NSRect(x: 0, y: 0, width: 736, height: 496)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scan Log — \(root.standardizedURL.lastPathComponent)"
        window.contentView = scrollView
        window.center()
        window.isReleasedWhenClosed = false
        scanLogWindows[id] = window
        window.makeKeyAndOrderFront(nil)
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
        runModernLibraryScan(for: [root], mode: .newScan)
    }

    func scanLibraryRoot(_ id: Int64) {
        guard let root = libraryScanRoots.first(where: { $0.id == id }) else { return }
        runModernLibraryScan(for: [root], mode: .newScan)
    }

    func retryFailedLibraryRoot(_ id: Int64) {
        guard let root = libraryScanRoots.first(where: { $0.id == id }) else { return }
        runModernLibraryScan(for: [root], mode: .retryFailed)
    }

    func trimMissingLibrary() {
        guard !libraryScanInProgress,
              let libraryDatabase else { return }
        let sources = (try? libraryDatabase.indexedSources()) ?? []
        let progressWindow = LibraryScanProgressWindowController(
            title: "CocoaSpice Library Integrity",
            onCancel: { [weak self] in self?.stopLibraryScan() }
        )
        libraryScanGeneration += 1
        let generation = libraryScanGeneration
        libraryScanInProgress = true
        libraryScanProgressWindow = progressWindow
        progressWindow.show()
        progressWindow.append("Checking \(sources.count) indexed source files…")

        libraryScanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                progressWindow.close()
                if self.libraryScanProgressWindow === progressWindow {
                    self.libraryScanProgressWindow = nil
                }
                if generation == self.libraryScanGeneration {
                    self.libraryScanInProgress = false
                }
            }
            let integrityTask = Task.detached(priority: .utility) {
                await LibraryIntegrityChecker.check(
                    sources: sources,
                    progress: { current, total, detail in
                        Task { @MainActor in
                            progressWindow.setProgress(current: current, total: total)
                            if current == 1 || current == total || current.isMultiple(of: 100) {
                                progressWindow.append("Checking \(current)/\(total): \(detail)")
                            }
                        }
                    }
                )
            }
            let result = await withTaskCancellationHandler {
                await integrityTask.value
            } onCancel: {
                integrityTask.cancel()
            }
            guard generation == self.libraryScanGeneration, !Task.isCancelled else { return }
            do {
                try libraryDatabase.trimMissingPaths(result.missingSources)
                self.trimmedLibraryScanRootIDs.formUnion(result.missingSources.map(\.rootID))
                self.persistTrimmedLibraryRootIDs()
                self.reloadLibraryScanRoots()
                self.reloadDatabaseGameItems()
                self.libraryScanStatus = "Trim Missing • \(result.checkedCount) sources checked • \(result.missingSources.count) missing removed"
                progressWindow.append("Removed \(result.missingSources.count) missing entries.")
            } catch {
                self.libraryScanStatus = "Integrity check failed: \(error.localizedDescription)"
                progressWindow.append(self.libraryScanStatus ?? "Integrity check failed.")
            }
        }
    }

    func rescanEnabledLibraryRoots() {
        runModernLibraryScan(for: libraryScanRoots.filter(\.isEnabled), mode: .newScan)
    }

    func stopLibraryScan() {
        guard libraryScanInProgress else { return }
        libraryScanGeneration += 1
        libraryScanTask?.cancel()
        libraryScanTask = nil
        libraryScanInProgress = false
        libraryScanStatus = "Scan stopped"
    }

    private func runModernLibraryScan(for roots: [LibraryScanRoot], mode: ScanMode) {
        guard !roots.isEmpty, let libraryDatabase else {
            libraryScanStatus = "Library database unavailable."
            return
        }
        libraryScanTask?.cancel()
        libraryScanGeneration += 1
        let generation = libraryScanGeneration
        libraryScanInProgress = true
        let progressWindow = LibraryScanProgressWindowController(
            title: "CocoaSpice Scan",
            onCancel: { [weak self] in self?.stopLibraryScan() }
        )
        libraryScanProgressWindow = progressWindow
        progressWindow.show()
        libraryScanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                progressWindow.close()
                if self.libraryScanProgressWindow === progressWindow {
                    self.libraryScanProgressWindow = nil
                }
            }
            for root in roots {
                guard generation == self.libraryScanGeneration, !Task.isCancelled else { return }
                let coordinator = LibraryScanCoordinator(database: libraryDatabase)
                self.libraryScanStatus = "Preparing \(mode.rawValue) scan: \(root.standardizedURL.lastPathComponent)…"
                progressWindow.append(self.libraryScanStatus ?? "Preparing scan…")
                do {
                    let summary = try await coordinator.run(root: root, mode: mode) { [weak self] status in
                        self?.libraryScanStatus = status
                        progressWindow.append(status)
                    } progress: { current, total in
                        progressWindow.setProgress(current: current, total: total)
                    }
                    guard generation == self.libraryScanGeneration else { return }
                    let issues = summary.failures.map {
                        "\($0.identity.path)\($0.identity.archiveEntry.map { "#\($0)" } ?? ""): \($0.stage.rawValue): \($0.message)"
                    }
                    // Progress is measured in scan candidates (files/archives),
                    // while a successful archive can yield many playable leaves.
                    LibraryScanLogStore.write(root: root, startedAt: root.lastScanStartedAt ?? Date(), completedFileCount: summary.discovered, totalFileCount: summary.discovered, issues: issues)
                    self.libraryScanStatus = "\(mode.rawValue.capitalized) scan \(root.standardizedURL.lastPathComponent) • \(summary.successful) successful • \(summary.failed) failed • \(summary.unsupported) unsupported"
                    self.trimmedLibraryScanRootIDs.remove(root.id)
                    self.persistTrimmedLibraryRootIDs()
                    self.reloadLibraryScanRoots()
                    self.reloadDatabaseGameItems()
                } catch is CancellationError {
                    guard generation == self.libraryScanGeneration else { return }
                    self.libraryScanStatus = "Scan cancelled"
                    return
                } catch {
                    guard generation == self.libraryScanGeneration else { return }
                    self.libraryScanStatus = "Scan failed for \(root.standardizedURL.lastPathComponent): \(error.localizedDescription)"
                    try? libraryDatabase.markScanFailed(rootID: root.id, error: error.localizedDescription)
                    self.reloadLibraryScanRoots()
                }
            }
            if generation == self.libraryScanGeneration {
                self.libraryScanInProgress = false
            }
        }
    }

    private func loadRoot(url: URL) {
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
        folderSelectionTask?.cancel()
        folderSelectionGeneration += 1
        let generation = folderSelectionGeneration
        let shouldQueue = playlistFollowsCursor
        statusText = shouldQueue
            ? "Loading \(folderURL.lastPathComponent)..."
            : "Browsing \(folderURL.lastPathComponent)..."

        folderSelectionTask = Task { [weak self] in
            guard let self else { return }
            let tracks = await PlaylistQueueLoader.loadTracks(in: folderURL)
            guard !Task.isCancelled else { return }
            guard generation == self.folderSelectionGeneration,
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
        }
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
            let selectedItems = databaseGameItems.filter { selectedDatabaseGameIDs.contains($0.id) }
            if !selectedItems.isEmpty {
                activateDatabaseGames(selectedItems, replace: true)
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

    private func activateDatabaseGames(_ items: [DatabaseGameItem], replace: Bool) {
        guard !items.isEmpty else { return }
        let selectedIDs = items.map(\.id)
        selectedDatabaseGameIDs = Set(selectedIDs)
        selectedDatabaseGameID = selectedIDs.last
        queueBuildTask?.cancel()
        queueBuildGeneration += 1
        let generation = queueBuildGeneration
        let label = items.count == 1 ? items[0].displayName : "\(items.count) games"
        statusText = "Loading \(label)..."
        let databaseURL = libraryDatabaseURL
        let gameItems = items

        queueBuildTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await PlaylistQueueLoader.loadLibraryTracksForGames(
                databaseURL: databaseURL,
                gameItems: gameItems
            )
            let tracks = loaded.tracks
            guard !Task.isCancelled, generation == self.queueBuildGeneration else { return }
            self.applyQueuedTracks(
                tracks,
                from: URL(fileURLWithPath: label, isDirectory: true),
                replace: replace,
                preservePlayback: replace,
                seedMetadataCache: loaded.metadata,
                widthHints: loaded.widthHints
            )
            self.statusText = replace
                ? "Queued \(tracks.count) tracks from \(label)"
                : "Enqueued \(tracks.count) tracks from \(label)"
        }
    }

    func queueFolder(_ folderURL: URL, replace: Bool = true, preservePlayback: Bool = false) {
        if let rootPath = libraryRootPath(for: folderURL) {
            queueLibraryFolder(folderURL, rootPath: rootPath, replace: replace, preservePlayback: preservePlayback)
            return
        }

        queueBuildTask?.cancel()
        queueBuildGeneration += 1
        let generation = queueBuildGeneration
        statusText = "Loading \(folderURL.lastPathComponent)..."

        queueBuildTask = Task { [weak self] in
            guard let self else { return }
            let tracks = await PlaylistQueueLoader.loadTracks(in: folderURL)
            guard !Task.isCancelled else { return }
            guard generation == self.queueBuildGeneration else { return }
            self.applyQueuedTracks(tracks, from: folderURL, replace: replace, preservePlayback: preservePlayback)
        }
    }

    func importDroppedURLs(_ urls: [URL]) {
        let normalizedURLs = urls.map(\.standardizedFileURL).filter(PlaylistQueueLoader.canImportDroppedURL(_:))
        guard !normalizedURLs.isEmpty else {
            statusText = "Drop contains no supported files."
            return
        }

        queueBuildTask?.cancel()
        queueBuildGeneration += 1
        let generation = queueBuildGeneration
        let sourceLabel = normalizedURLs.count == 1
            ? normalizedURLs[0].lastPathComponent
            : "\(normalizedURLs.count) dropped items"
        statusText = "Importing \(sourceLabel)..."

        queueBuildTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await PlaylistQueueLoader.loadDroppedTracks(from: normalizedURLs)
            guard !Task.isCancelled else { return }
            guard generation == self.queueBuildGeneration else { return }
            guard !loaded.tracks.isEmpty else {
                self.statusText = "No supported tracks in \(sourceLabel)"
                return
            }

            self.appendTracksToPlaylist(
                loaded.tracks,
                status: "Imported \(loaded.tracks.count) track\(loaded.tracks.count == 1 ? "" : "s") from \(sourceLabel)",
                seedMetadataCache: loaded.metadata,
                widthHints: loaded.widthHints
            )
        }
    }

    private func applyQueuedTracks(
        _ tracks: [TrackItem],
        from folderURL: URL,
        replace: Bool,
        preservePlayback: Bool = false,
        seedMetadataCache: [String: TrackMetadata] = [:],
        widthHints: PlaylistColumnWidthHints? = nil
    ) {
        guard !tracks.isEmpty else {
            statusText = "No supported tracks in \(folderURL.lastPathComponent)"
            return
        }

        metadataCache = seedMetadataCache
        playlistColumnWidthHints = widthHints

        if replace {
            if !preservePlayback {
                playbackTask?.cancel()
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
            }
            playlist = tracks
            syncManualPlaylistOrder()
            reapplyPlaylistSortIfNeeded()
            if let currentTrack,
               playlist.contains(where: { $0.id == currentTrack.id }) {
                selectedTrackID = currentTrack.id
            } else {
                selectedTrackID = tracks.first?.id
            }
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
    }

    private func appendTracksToPlaylist(
        _ tracks: [TrackItem],
        status: String,
        seedMetadataCache: [String: TrackMetadata] = [:],
        widthHints: PlaylistColumnWidthHints? = nil
    ) {
        let existing = Set(playlist.map(\.id))
        let uniqueTracks = tracks.filter { !existing.contains($0.id) }
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

    var canRevealSelectedTracksInFinder: Bool {
        !orderedSelectedPlaylistTracks().isEmpty
    }

    var canExportSelectedTracksToAAC: Bool {
        !orderedSelectedPlaylistTracks().isEmpty && audioExportTask == nil
    }

    var canDragReorderTracks: Bool {
        playlistSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
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

    func revealSelectedTracksInFinder() {
        let tracks = orderedSelectedPlaylistTracks()
        guard !tracks.isEmpty else { return }

        NSWorkspace.shared.activateFileViewerSelecting(tracks.map(\.url))
        statusText = "Revealed \(tracks.count) track\(tracks.count == 1 ? "" : "s") in Finder"
    }

    func exportSelectedTracksToAAC() {
        exportTracksToAAC(orderedSelectedPlaylistTracks())
    }

    func savePreferencesNow() {
        AppSessionPersistence.savePlaybackPreferences(
            longPlayEnabled: longPlayEnabled,
            playlistFollowsCursor: playlistFollowsCursor,
            manualPreFadeSeconds: manualPreFadeSeconds,
            spectrumGradientStartColor: spectrumGradientStartColor,
            spectrumGradientEndColor: spectrumGradientEndColor,
            spectrumPeakColor: spectrumPeakColor,
            sidebarDoubleClickActionRawValue: sidebarDoubleClickAction.rawValue,
            lastAudioExportDirectoryPath: lastAudioExportDirectoryURL?.path,
            databaseSidebarFontSize: databaseSidebarFontSize
            ,databaseSidebarTextColor: databaseSidebarTextColor.rawValue
        )
    }

    func setDatabaseSidebarFontSize(_ size: CGFloat) {
        databaseSidebarFontSize = size
        savePreferencesNow()
    }

    func setDatabaseSidebarTextColor(_ color: DatabaseSidebarTextColor) {
        databaseSidebarTextColor = color
        savePreferencesNow()
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
        windowController.present(
            snapshot: AudioExportProgressSnapshot(
                title: "Preparing AAC export",
                detail: outputDirectory.path,
                progress: nil
            )
        )
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
                        self?.audioExportWindowController?.apply(snapshot: snapshot)
                    }
                }

                await MainActor.run {
                    self.audioExportWindowController?.apply(
                        snapshot: AudioExportProgressSnapshot(
                            title: "AAC export complete",
                            detail: result.outputDirectory.path,
                            progress: 1
                        )
                    )
                    self.audioExportWindowController?.closeAutomatically()
                    self.statusText = "Exported \(result.exportedCount) AAC file\(result.exportedCount == 1 ? "" : "s")"
                    self.audioExportTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.audioExportWindowController?.apply(
                        snapshot: AudioExportProgressSnapshot(
                            title: "AAC export cancelled",
                            detail: outputDirectory.path,
                            progress: nil
                        )
                    )
                    self.audioExportWindowController?.closeAutomatically()
                    self.statusText = "AAC export cancelled"
                    self.audioExportTask = nil
                }
            } catch {
                await MainActor.run {
                    self.audioExportWindowController?.apply(
                        snapshot: AudioExportProgressSnapshot(
                            title: "AAC export failed",
                            detail: outputDirectory.path,
                            progress: nil
                        )
                    )
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
        guard !isLoading, isPlaying else { return }
        let playback = self.playback
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = await playback.togglePause()
            self.statusText = "Paused"
            self.updateRemoteTransportState()
        }
    }

    func resumePlayback() {
        guard !isLoading else { return }

        guard let currentTrack else {
            guard let track = transportPlaybackTarget else { return }
            currentTrack = track
            selectedTrackID = track.id
            requestPlayback(for: track)
            return
        }

        if !isPlaying, playbackElapsedSeconds == 0 {
            requestPlayback(for: currentTrack)
            return
        }

        guard !isPlaying else { return }
        let playback = self.playback
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = await playback.togglePause()
            self.statusText = "Playing"
            self.updateRemoteTransportState()
        }
    }

    func toggleTrackPlayback(_ track: TrackItem) {
        if currentTrack?.id == track.id, isPlaying {
            playbackTask?.cancel()
            pendingPlaybackTrack = nil
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
        selectedTrackID = track.id
        didAutoAdvanceForCurrentTrack = false
        requestPlayback(for: track)
    }

    func playNext() {
        guard let nextTrack = QueueTransportNavigation.adjacentTrack(
            from: transportNavigationAnchor,
            in: playlist,
            direction: .next,
            wraps: true
        ) else { return }
        selectedTrackID = nextTrack.id
        requestPlayback(for: nextTrack)
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
        selectedTrackID = previousTrack.id
        requestPlayback(for: previousTrack)
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
        if currentTrackSupportsLongPlay {
            applyPlaybackTiming()
        }
    }

    func applyPlaybackTiming() {
        guard let currentTrack, !isLoading else { return }
        playbackTask?.cancel()
        isPlaying = false
        toolbarSpectrum.reset()
        isSeeking = false
        playbackElapsedSeconds = 0
        seekPreviewSeconds = 0
        didAutoAdvanceForCurrentTrack = false
        currentMetadata = nil
        updateRemoteTransportState()
        requestPlayback(for: currentTrack)
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
        if isLoading, currentTrack?.id == track.id {
            return
        }

        playbackTask?.cancel()
        playbackRequestGeneration += 1
        let generation = playbackRequestGeneration
        pendingPlaybackTrack = track
        selectedTrackID = track.id
        selectedTrackIDs = [track.id]
        isPlaying = false
        toolbarSpectrum.reset()
        didAutoAdvanceForCurrentTrack = false
        isLoading = true
        statusText = "Rendering \(track.filename)..."

        let playback = self.playback
        let requestID = playback.reservePlaybackRequest()
        playbackTask = Task { [weak self] in
            await playback.stopPlayback()
            guard !Task.isCancelled else { return }
            guard let self, generation == self.playbackRequestGeneration else { return }
            await self.play(track: track, generation: generation, requestID: requestID)
        }
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
            guard generation == playbackRequestGeneration else { return }

            let plan = playbackPlan(for: seedMetadata, trackPathExtension: track.playablePathExtension)
            let loadedMetadata = try await playback.play(track: track, plan: plan, requestID: requestID)
            guard generation == playbackRequestGeneration else { return }
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
            if generation == playbackRequestGeneration {
                isPlaying = await playback.statusSnapshot().isPlaying
                updateRemoteTransportState()
            }
        } catch {
            isPlaying = false
            statusText = error.localizedDescription
            updateRemoteTransportState()
        }

        if generation == playbackRequestGeneration {
            isLoading = false
            playbackTask = nil
        }
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
        return GMEFormatSupport.supportedExtensions.contains(extensionName.lowercased())
    }

    var effectivePreFadeSeconds: Int {
        playbackPlan(for: currentMetadata, trackPathExtension: currentTrack?.playablePathExtension).preFadeSeconds
    }

    var totalPlaybackSeconds: Int {
        effectivePreFadeSeconds + fadeSeconds
    }

    var elapsedReadout: String {
        "\(Self.formatTime(Int(displayedElapsedSeconds.rounded()))) / \(Self.formatTime(totalPlaybackSeconds))"
    }

    var statusPathReadout: String {
        let track = currentTrack ?? transportPlaybackTarget
        guard let track else { return "" }
        return track.statusPathText
    }

    var visiblePlaylist: [TrackItem] {
        visiblePlaylistItems
    }

    func libraryScanRootStatusText(_ root: LibraryScanRoot) -> String {
        let order = (libraryScanRoots.firstIndex(where: { $0.id == root.id }) ?? 0) + 1
        return DatabaseSidebarPresentation.scanRootStatusText(root, order: order)
    }

    func libraryScanRootIsClean(_ root: LibraryScanRoot) -> Bool {
        cleanLibraryScanRootIDs.contains(root.id) && root.lastScanError == nil
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
                let playback = self.playback
                let snapshot = await playback.statusSnapshot()
                if !self.isSeeking {
                    self.playbackElapsedSeconds = snapshot.elapsedSeconds
                }
                if !snapshot.isPlaying {
                    self.toolbarSpectrum.reset()
                }
                self.handlePlaybackCompletionIfNeeded()
                self.updateRemoteTransportState()
            }
        }
    }

    private func handlePlaybackCompletionIfNeeded() {
        guard !isLoading,
              !isSeeking,
              !isPlaying,
              !didAutoAdvanceForCurrentTrack,
              let currentTrack,
              !playlist.isEmpty else {
            return
        }

        guard QueueTransportNavigation.reachedCompletionThreshold(
            elapsedSeconds: playbackElapsedSeconds,
            totalPlaybackSeconds: totalPlaybackSeconds
        ) else { return }

        didAutoAdvanceForCurrentTrack = true
        let nextTrack = QueueTransportNavigation.completionAdvanceTarget(
            currentTrack: currentTrack,
            selectedTrackID: selectedTrackID,
            playlist: playlist
        )
        guard let nextTrack else { return }
        selectedTrackID = nextTrack.id
        requestPlayback(for: nextTrack)
    }

    private func libraryRootPath(for folderURL: URL) -> String? {
        let normalizedFolderPath = folderURL.standardizedFileURL.path
        return enabledLibraryRootURLs
            .map(\.path)
            .first(where: { normalizedFolderPath == $0 || normalizedFolderPath.hasPrefix($0 + "/") })
    }

    private func queueLibraryFolder(_ folderURL: URL, rootPath: String, replace: Bool, preservePlayback: Bool) {
        queueBuildTask?.cancel()
        queueBuildGeneration += 1
        let generation = queueBuildGeneration
        statusText = "Loading \(folderURL.lastPathComponent)..."
        let databaseURL = libraryDatabaseURL
        let folderPath = folderURL.path

        queueBuildTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await PlaylistQueueLoader.loadLibraryTracksForFolder(
                databaseURL: databaseURL,
                rootPath: rootPath,
                folderPath: folderPath
            )
            guard !Task.isCancelled, generation == self.queueBuildGeneration else { return }
            self.applyQueuedTracks(
                loaded.tracks,
                from: folderURL,
                replace: replace,
                preservePlayback: preservePlayback,
                seedMetadataCache: loaded.metadata,
                widthHints: loaded.widthHints
            )
        }
    }

    private func queueLibraryTracks(forPaths paths: [String], replace: Bool) {
        let normalizedPaths = Array(NSOrderedSet(array: paths.map {
            URL(fileURLWithPath: $0, isDirectory: false).standardizedFileURL.path
        })) as? [String] ?? []
        guard !normalizedPaths.isEmpty else { return }

        queueBuildTask?.cancel()
        queueBuildGeneration += 1
        let generation = queueBuildGeneration
        let label = normalizedPaths.count == 1
            ? URL(fileURLWithPath: normalizedPaths[0]).lastPathComponent
            : "\(normalizedPaths.count) files"
        statusText = "Loading \(label)..."
        let databaseURL = libraryDatabaseURL

        queueBuildTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await PlaylistQueueLoader.loadLibraryTracksForPaths(
                databaseURL: databaseURL,
                paths: normalizedPaths
            )
            guard !Task.isCancelled, generation == self.queueBuildGeneration else { return }
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
        }
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

    private func refreshPlaylistMetadata() {
        playlistLoadTask?.cancel()
        playlistLoadGeneration += 1
        let generation = playlistLoadGeneration
        let tracks = playlist
        let cachedMetadata = metadataCache

        guard !tracks.isEmpty else {
            playlistColumnWidthHints = nil
            playlistMetadataLoadToken += 1
            return
        }

        let missingTracks = tracks.filter { cachedMetadata[$0.id] == nil }
        if missingTracks.isEmpty {
            if playlistColumnWidthHints == nil {
                playlistColumnWidthHints = Self.buildPlaylistColumnWidthHints(
                    tracks: tracks,
                    metadata: cachedMetadata
                )
            }
            playlistMetadataLoadToken += 1
            return
        }

        playlistLoadTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var resolvedMetadata = cachedMetadata
            await withTaskGroup(of: (String, TrackMetadata?).self) { group in
                for track in missingTracks {
                    group.addTask {
                        let metadata = try? await PlaybackInspection.inspectMetadata(track: track)
                        return (track.id, metadata)
                    }
                }

                for await (trackID, metadata) in group {
                    if Task.isCancelled {
                        break
                    }

                    guard let metadata else { continue }
                    resolvedMetadata[trackID] = metadata
                    await MainActor.run {
                        guard generation == self.playlistLoadGeneration else { return }
                        self.updatePlaylistMetadata(for: trackID, metadata: metadata)
                    }
                }
            }

            let widthHints = Self.buildPlaylistColumnWidthHints(
                tracks: tracks,
                metadata: resolvedMetadata
            )

            await MainActor.run {
                guard generation == self.playlistLoadGeneration else { return }
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
            }
        }
    }

    private func updatePlaylistMetadata(for trackID: String, metadata: TrackMetadata) {
        metadataCache[trackID] = metadata
    }

    private func scheduleVisiblePlaylistRefresh() {
        visiblePlaylistTask?.cancel()
        visiblePlaylistGeneration += 1
        let generation = visiblePlaylistGeneration
        let tracks = playlist
        let metadata = metadataCache
        let query = playlistSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            visiblePlaylistItems = tracks
            return
        }

        visiblePlaylistTask = Task { [weak self] in
            let filtered = await Task.detached(priority: .userInitiated) {
                Self.filterPlaylistTracks(tracks, metadata: metadata, query: query)
            }.value
            guard let self else { return }
            guard !Task.isCancelled, generation == self.visiblePlaylistGeneration else { return }
            self.visiblePlaylistItems = filtered
        }
    }

    private func syncManualPlaylistOrder() {
        playlistManualOrder = Dictionary(
            uniqueKeysWithValues: playlist.enumerated().map { ($1.id, $0) }
        )
    }

    private func reloadLibraryScanRoots() {
        guard let libraryDatabase else { return }
        do {
            libraryScanRoots = try libraryDatabase.loadRoots()
            cleanLibraryScanRootIDs = Set(libraryScanRoots.compactMap { root in
                root.lastScanCompletedAt != nil && LibraryScanLogStore.reportsNoIssues(rootID: root.id) ? root.id : nil
            })
            trimmedLibraryScanRootIDs.formIntersection(Set(libraryScanRoots.map(\.id)))
            persistTrimmedLibraryRootIDs()
        } catch {
            libraryScanStatus = "Could not load scan roots: \(error.localizedDescription)"
        }
    }

    private func reloadDatabaseGameItems() {
        databaseGameItems = (try? libraryDatabase?.loadGameItems()) ?? []
        visibleDatabaseGameItems = databaseGameItems
        if let selectedDatabaseGameID,
           !databaseGameItems.contains(where: { $0.id == selectedDatabaseGameID }) {
            self.selectedDatabaseGameID = nil
            self.selectedDatabaseGameIDs = []
        }
        handleSidebarSearchChanged()
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
        rootURL = nil
        selectedFolderPath = nil
        selectedDatabaseGameID = nil
        selectedDatabaseGameIDs = []
        databaseGameItems = []
        visibleDatabaseGameItems = []
        browsedFolderTracks = []
        playlist = []
        syncManualPlaylistOrder()
        metadataCache = [:]
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
        rootURL = nil
        selectedFolderPath = nil
        selectedDatabaseGameID = nil
        selectedDatabaseGameIDs = []
        browsedFolderTracks = []
        sidebarSearchText = ""
        playlistColumnWidthHints = nil
        statusText = message
    }

    private func restorePlaybackPreferences() {
        let preferences = AppSessionPersistence.restorePlaybackPreferences()
        longPlayEnabled = preferences.longPlayEnabled
        playlistFollowsCursor = preferences.playlistFollowsCursor
        if let storedManualPreFade = preferences.manualPreFadeSeconds {
            manualPreFadeSeconds = storedManualPreFade
        }
        if let storedStartColor = preferences.spectrumGradientStartColor.flatMap(AppSessionPersistence.deserializeColor) {
            spectrumGradientStartColor = storedStartColor
        }
        if let storedEndColor = preferences.spectrumGradientEndColor.flatMap(AppSessionPersistence.deserializeColor) {
            spectrumGradientEndColor = storedEndColor
        }
        if let storedPeakColor = preferences.spectrumPeakColor.flatMap(AppSessionPersistence.deserializeColor) {
            spectrumPeakColor = storedPeakColor
        }
        if let storedAction = preferences.sidebarDoubleClickActionRawValue.flatMap(SidebarDoubleClickAction.init(rawValue:)) {
            sidebarDoubleClickAction = storedAction
        }
        if let lastAudioExportDirectoryPath = preferences.lastAudioExportDirectoryPath {
            lastAudioExportDirectoryURL = URL(fileURLWithPath: lastAudioExportDirectoryPath, isDirectory: true).standardizedFileURL
        }
        if let storedSidebarFontSize = preferences.databaseSidebarFontSize {
            databaseSidebarFontSize = CGFloat(storedSidebarFontSize)
        }
        if let storedSidebarTextColor = preferences.databaseSidebarTextColor.flatMap(DatabaseSidebarTextColor.init(rawValue:)) {
            databaseSidebarTextColor = storedSidebarTextColor
        }
        if let storedSortColumn = preferences.playlistSortColumnRawValue.flatMap(PlaylistSortColumn.init(rawValue:)) {
            playlistSortColumn = storedSortColumn
        }
        if let storedSortDirection = preferences.playlistSortDirectionRawValue.flatMap(PlaylistSortDirection.init(rawValue:)) {
            playlistSortDirection = storedSortDirection
        }
    }

    func saveSessionStateNow() {
        AppSessionPersistence.saveSessionState(
            playlist: playlist,
            selectedTrackID: selectedTrackID,
            currentTrackID: currentTrack?.id,
            rootPath: rootURL?.path,
            selectedFolderPath: selectedFolderPath,
            librarySelectedFolderPath: librarySelectedFolderPath,
            sidebarSearchText: sidebarSearchText,
            playlistSearchText: playlistSearchText
        )
        savePreferencesNow()
        AppSessionPersistence.savePlaylistColumnState(
            order: pendingPlaylistColumnOrder,
            visibility: pendingPlaylistColumnVisibility,
            widths: pendingPlaylistColumnWidths
        )
    }

    private func restorePlaylistColumnState() {
        let state = AppSessionPersistence.restorePlaylistColumnState()
        pendingPlaylistColumnOrder = state.order
        pendingPlaylistColumnVisibility = state.visibility
        pendingPlaylistColumnWidths = state.widths
    }

    private func restorePersistedPlaylist() {
        guard let session = AppSessionPersistence.restoreSessionState(
            supportedExtensions: SPCFileScanner.supportedExtensions
        ) else { return }
        playlist = session.tracks
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
        playlistColumnWidthHints = nil
        refreshPlaylistMetadata()
    }

    private func orderedSelectedPlaylistTracks() -> [TrackItem] {
        playlist.filter { selectedTrackIDs.contains($0.id) }
    }

    private func ensureAudioExportWindowController() -> AudioExportProgressWindowController {
        if let audioExportWindowController {
            return audioExportWindowController
        }
        let controller = AudioExportProgressWindowController()
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
        playlistColumnWidthHints = nil
        refreshPlaylistMetadata()
        statusText = status
        updateRemoteTransportState()
    }

    private func handleSidebarSearchChanged() {
        visibleDatabaseGameItems = DatabaseSidebarPresentation.filterGameItems(
            databaseGameItems,
            query: sidebarSearchText
        )
    }

    var isLibraryScanInProgress: Bool {
        libraryScanInProgress
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
            supportedExtensions: SPCFileScanner.supportedExtensions
        )

        guard !tracks.isEmpty else { return }
        playbackTask?.cancel()
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
        playlistColumnWidthHints = nil
        refreshPlaylistMetadata()
        statusText = "Loaded playlist \(url.lastPathComponent)"
        updateRemoteTransportState()
    }

    private func restoreInitialSidebarMode() {
        librarySelectedFolderPath = AppSessionPersistence.lastLibrarySelectedFolderPath()

        let enabledRoots = libraryScanRoots.filter(\.isEnabled)
        if let restoredRootPath = AppSessionPersistence.lastRootPath(),
           let restoredRoot = enabledRoots.first(where: { $0.standardizedURL.path == restoredRootPath }) {
            let restoredSelection = AppSessionPersistence.lastLibrarySelectedFolderPath()
            loadRoot(url: restoredRoot.standardizedURL)
            if let restoredSelection,
               restoredSelection.hasPrefix(restoredRoot.standardizedURL.path) {
                selectedFolderPath = restoredSelection
                librarySelectedFolderPath = restoredSelection
            }
        } else if let firstEnabledRoot = enabledRoots.first {
            let restoredSelection = AppSessionPersistence.lastLibrarySelectedFolderPath()
            loadRoot(url: firstEnabledRoot.standardizedURL)
            if let restoredSelection,
               restoredSelection.hasPrefix(firstEnabledRoot.standardizedURL.path) {
                selectedFolderPath = restoredSelection
                librarySelectedFolderPath = restoredSelection
            }
        } else {
            clearLibraryState()
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
        case .index, .file:
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

    func indexText(for track: TrackItem) -> String {
        guard let index = playlist.firstIndex(of: track) else { return "—" }
        return String(index + 1)
    }

    nonisolated private static func filterPlaylistTracks(
        _ tracks: [TrackItem],
        metadata: [String: TrackMetadata],
        query: String
    ) -> [TrackItem] {
        PlaylistPresentation.filterTracks(tracks, metadata: metadata, query: query)
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
            remoteTransport.configure(with: self)
            remoteTransportConfigured = true
        }
        remoteTransport.updateNowPlaying(from: self)
    }
}
