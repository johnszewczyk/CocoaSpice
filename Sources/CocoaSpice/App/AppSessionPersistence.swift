import AppKit
import Foundation
import VGMBoyKit

enum AppDefaultsKey {
    static let libraryDatabasePath = "CocoaSpice.libraryDatabasePath"
    static let lastRootPath = "CocoaSpice.lastRootPath"
    static let lastSelectedFolderPath = "CocoaSpice.lastSelectedFolderPath"
    static let lastLibrarySelectedFolderPath = "CocoaSpice.lastLibrarySelectedFolderPath"
    static let sidebarSearchText = "CocoaSpice.sidebarSearchText"
    static let playlistSearchText = "CocoaSpice.playlistSearchText"
    static let longPlayEnabled = "CocoaSpice.longPlayEnabled"
    static let manualPreFadeSeconds = "CocoaSpice.manualPreFadeSeconds"
    static let unknownDurationSeconds = "CocoaSpice.unknownDurationSeconds"
    static let endFadeEnabled = "CocoaSpice.endFadeEnabled"
    static let fadeSeconds = "CocoaSpice.fadeSeconds"
    static let fadedSkipEnabled = "CocoaSpice.fadedSkipEnabled"
    static let equalizerEnabled = "CocoaSpice.equalizerEnabled"
    static let equalizerBandGains = "CocoaSpice.equalizerBandGains"
    static let appVolume = "CocoaSpice.appVolume"
    static let monoEnabled = "CocoaSpice.monoEnabled"
    static let randomPlaybackScope = "CocoaSpice.randomPlaybackScope"
    static let repeatMode = "CocoaSpice.repeatMode"
    static let sidebarDoubleClickAction = "CocoaSpice.sidebarDoubleClickAction"
    static let playlistFollowsCursor = "CocoaSpice.playlistFollowsCursor"
    static let playlistSortColumn = "CocoaSpice.playlistSortColumn"
    static let playlistSortDirection = "CocoaSpice.playlistSortDirection"
    static let persistedPlaylistPaths = "CocoaSpice.persistedPlaylistPaths"
    static let persistedSelectedTrackPath = "CocoaSpice.persistedSelectedTrackPath"
    static let persistedCurrentTrackPath = "CocoaSpice.persistedCurrentTrackPath"
    static let playlistColumnOrder = "CocoaSpice.playlistColumnOrder"
    static let playlistColumnVisibility = "CocoaSpice.playlistColumnVisibility"
    static let playlistColumnWidths = "CocoaSpice.playlistColumnWidths"
    static let databaseSidebarFontSize = "CocoaSpice.databaseSidebarFontSize"
    static let databaseSidebarTextColor = "CocoaSpice.databaseSidebarTextColor"
    static let databaseSidebarMonospaceFont = "CocoaSpice.databaseSidebarMonospaceFont"
    static let databaseSidebarDisclosureGap = "CocoaSpice.databaseSidebarDisclosureGap"
    static let databaseSidebarDisclosureGapPoints = "CocoaSpice.databaseSidebarDisclosureGapPoints"
    static let databaseSidebarChildIndentPoints = "CocoaSpice.databaseSidebarChildIndentPoints"
    static let databaseSidebarHidesFileExtensions = "CocoaSpice.databaseSidebarHidesFileExtensions"
    static let playlistFontSize = "CocoaSpice.playlistFontSize"
    static let playlistTextColor = "CocoaSpice.playlistTextColor"
    static let playlistMonospaceFont = "CocoaSpice.playlistMonospaceFont"
    static let sidebarSystemMode = "CocoaSpice.sidebarSystemMode"
    static let preferEmbeddedConsoleTags = "CocoaSpice.preferEmbeddedConsoleTags"
    static let sidebarBrowserMode = "CocoaSpice.sidebarBrowserMode"
    static let favoriteSortOrder = "CocoaSpice.favoriteSortOrder"
    static let localBrowserEnabled = "CocoaSpice.localBrowserEnabled"
    static let localBrowserPath = "CocoaSpice.localBrowserPath"
    static let autoResizeAnimationMilliseconds = "CocoaSpice.autoResizeAnimationMilliseconds"
    static let selectionAnimationMilliseconds = "CocoaSpice.selectionAnimationMilliseconds"
    static let autoResizeAnimationEnabled = "CocoaSpice.autoResizeAnimationEnabled"
    static let selectionAnimationEnabled = "CocoaSpice.selectionAnimationEnabled"
    static let columnAutoSize = "CocoaSpice.columnAutoSize"
    static let mainWindowAlwaysOnTop = "CocoaSpice.mainWindowAlwaysOnTop"
    static let settingsWindowAlwaysOnTop = "CocoaSpice.settingsWindowAlwaysOnTop"
    static let archiveCacheMode = "CocoaSpice.archiveCacheMode"
    static let archiveCacheLimitBytes = "CocoaSpice.archiveCacheLimitBytes"
    static let aacExportDirectory = "CocoaSpice.aacExportDirectory"
    static let libgmeTempoNumerator = "CocoaSpice.libgmeTempoNumerator"
    static let libgmeTempoDenominator = "CocoaSpice.libgmeTempoDenominator"
    static let libgmeTempoEnabled = "CocoaSpice.libgmeTempoEnabled"
    static let libvgmTempoNumerator = "CocoaSpice.libvgmTempoNumerator"
    static let libvgmTempoDenominator = "CocoaSpice.libvgmTempoDenominator"
    static let libvgmTempoEnabled = "CocoaSpice.libvgmTempoEnabled"
}

struct RestoredPlaybackPreferences {
    let longPlayEnabled: Bool
    let playlistFollowsCursor: Bool
    let manualPreFadeSeconds: Int?
    let unknownDurationSeconds: Int?
    let endFadeEnabled: Bool
    let fadeSeconds: Int
    let fadedSkipEnabled: Bool
    let equalizerEnabled: Bool
    let equalizerBandGains: [Double]?
    let appVolume: Double
    let monoEnabled: Bool
    let randomPlaybackScopeRawValue: String?
    let repeatModeRawValue: String?
    let sidebarDoubleClickActionRawValue: String?
    let playlistSortColumnRawValue: String?
    let playlistSortDirectionRawValue: String?
    let databaseSidebarFontSize: Double?
    let databaseSidebarTextColor: String?
    let databaseSidebarMonospaceFont: Bool
    let databaseSidebarDisclosureGap: Double?
    let databaseSidebarDisclosureGapPoints: Double?
    let databaseSidebarChildIndentPoints: Double?
    let databaseSidebarHidesFileExtensions: Bool
    let playlistFontSize: Double?
    let playlistTextColor: String?
    let playlistMonospaceFont: Bool
    let sidebarSystemMode: Bool
    let preferEmbeddedConsoleTags: Bool
    let sidebarBrowserModeRawValue: String?
    let libgmeTempo: PlaybackTempo
    let libgmeTempoEnabled: Bool
    let libvgmTempo: PlaybackTempo
    let libvgmTempoEnabled: Bool
}

struct RestoredSessionState {
    let tracks: [TrackItem]
    /// Startup must remain usable even if a prior action put an entire large
    /// library in the queue. The complete saved queue remains in preferences;
    /// this only records how many entries were deliberately deferred.
    let deferredTrackCount: Int
    let deferredPersistedValues: [String]
    let selectedTrackID: String?
    let currentTrackID: String?
    let lastSelectedFolderPath: String?
    let lastLibrarySelectedFolderPath: String?
}

struct RestoredPlaylistColumnState {
    let order: [String]
    let visibility: [String: Bool]
    let widths: [String: Double]
}

/// All persisted inputs required to restore an app launch deterministically.
struct RestoredAppStartupState {
    let playbackPreferences: RestoredPlaybackPreferences
    let sessionState: RestoredSessionState?
    let playlistColumnState: RestoredPlaylistColumnState
    let sidebarSearchText: String
    let lastRootPath: String?
    let lastLibrarySelectedFolderPath: String?
}

enum AppSessionPersistence {
    /// Launch restores a bounded visible queue. The untouched remainder stays
    /// persisted for the next save without forcing a large table construction.
    static let maximumRestoredPlaylistTracks = 1_024

    static func restorePlaybackPreferences(defaults: UserDefaults = .standard) -> RestoredPlaybackPreferences {
        func tempo(numeratorKey: String, denominatorKey: String) -> PlaybackTempo {
            PlaybackTempo(
                numerator: defaults.object(forKey: numeratorKey) as? Int ?? 1,
                denominator: defaults.object(forKey: denominatorKey) as? Int ?? 1
            )
        }
        let storedLongPlaySeconds = defaults.integer(forKey: AppDefaultsKey.manualPreFadeSeconds)
        let storedUnknownDurationSeconds = defaults.integer(forKey: AppDefaultsKey.unknownDurationSeconds)
        let storedFadeSeconds = defaults.object(forKey: AppDefaultsKey.fadeSeconds)
            .flatMap { ($0 as? NSNumber)?.intValue } ?? PlaybackTimingPreferences.defaultFadeSeconds
        let storedEqualizerGains = defaults.array(forKey: AppDefaultsKey.equalizerBandGains) as? [NSNumber]
        let shared = PlaybackPreferences(
            timing: PlaybackTimingPreferences(
                longPlaySeconds: storedLongPlaySeconds > 0
                    ? storedLongPlaySeconds
                    : PlaybackTimingPreferences.defaultLongPlaySeconds,
                unknownDurationSeconds: storedUnknownDurationSeconds > 0
                    ? storedUnknownDurationSeconds
                    : PlaybackTimingPreferences.defaultUnknownDurationSeconds,
                fadeSeconds: PlaybackTimingPreferences.defaultFadeSeconds
            ),
            fadeEnabled: defaults.object(forKey: AppDefaultsKey.endFadeEnabled) as? Bool ?? true,
            equalizerEnabled: defaults.object(forKey: AppDefaultsKey.equalizerEnabled) as? Bool ?? false,
            equalizerBandGains: storedEqualizerGains?.map { $0.floatValue } ?? [],
            outputVolume: (defaults.object(forKey: AppDefaultsKey.appVolume) as? Double).map(Float.init) ?? 1,
            monoEnabled: defaults.object(forKey: AppDefaultsKey.monoEnabled) as? Bool ?? false,
            libgmeTempo: tempo(numeratorKey: AppDefaultsKey.libgmeTempoNumerator, denominatorKey: AppDefaultsKey.libgmeTempoDenominator),
            libgmeTempoEnabled: defaults.object(forKey: AppDefaultsKey.libgmeTempoEnabled) as? Bool ?? false,
            libvgmTempo: tempo(numeratorKey: AppDefaultsKey.libvgmTempoNumerator, denominatorKey: AppDefaultsKey.libvgmTempoDenominator),
            libvgmTempoEnabled: defaults.object(forKey: AppDefaultsKey.libvgmTempoEnabled) as? Bool ?? false
        )
        return RestoredPlaybackPreferences(
            longPlayEnabled: defaults.bool(forKey: AppDefaultsKey.longPlayEnabled),
            playlistFollowsCursor: defaults.object(forKey: AppDefaultsKey.playlistFollowsCursor) as? Bool ?? false,
            manualPreFadeSeconds: storedLongPlaySeconds > 0 ? shared.timing.longPlaySeconds : nil,
            unknownDurationSeconds: storedUnknownDurationSeconds > 0 ? shared.timing.unknownDurationSeconds : nil,
            endFadeEnabled: shared.fadeEnabled,
            fadeSeconds: max(0, storedFadeSeconds),
            fadedSkipEnabled: defaults.object(forKey: AppDefaultsKey.fadedSkipEnabled) as? Bool ?? false,
            equalizerEnabled: shared.equalizer.enabled,
            equalizerBandGains: storedEqualizerGains?.map {
                Double(PlaybackPreferences.clampedEqualizerGain($0.floatValue))
            },
            appVolume: Double(shared.outputVolume),
            monoEnabled: shared.monoEnabled,
            randomPlaybackScopeRawValue: defaults.string(forKey: AppDefaultsKey.randomPlaybackScope),
            repeatModeRawValue: defaults.string(forKey: AppDefaultsKey.repeatMode),
            sidebarDoubleClickActionRawValue: defaults.string(forKey: AppDefaultsKey.sidebarDoubleClickAction),
            playlistSortColumnRawValue: defaults.string(forKey: AppDefaultsKey.playlistSortColumn),
            playlistSortDirectionRawValue: defaults.string(forKey: AppDefaultsKey.playlistSortDirection),
            databaseSidebarFontSize: defaults.object(forKey: AppDefaultsKey.databaseSidebarFontSize) as? Double,
            databaseSidebarTextColor: defaults.string(forKey: AppDefaultsKey.databaseSidebarTextColor),
            databaseSidebarMonospaceFont: defaults.object(forKey: AppDefaultsKey.databaseSidebarMonospaceFont) as? Bool ?? false,
            databaseSidebarDisclosureGap: defaults.object(forKey: AppDefaultsKey.databaseSidebarDisclosureGap) as? Double,
            databaseSidebarDisclosureGapPoints: defaults.object(forKey: AppDefaultsKey.databaseSidebarDisclosureGapPoints) as? Double,
            databaseSidebarChildIndentPoints: defaults.object(forKey: AppDefaultsKey.databaseSidebarChildIndentPoints) as? Double,
            databaseSidebarHidesFileExtensions: defaults.object(forKey: AppDefaultsKey.databaseSidebarHidesFileExtensions) as? Bool ?? false,
            playlistFontSize: defaults.object(forKey: AppDefaultsKey.playlistFontSize) as? Double,
            playlistTextColor: defaults.string(forKey: AppDefaultsKey.playlistTextColor),
            playlistMonospaceFont: defaults.object(forKey: AppDefaultsKey.playlistMonospaceFont) as? Bool ?? false,
            sidebarSystemMode: defaults.object(forKey: AppDefaultsKey.sidebarSystemMode) as? Bool ?? false,
            preferEmbeddedConsoleTags: defaults.object(forKey: AppDefaultsKey.preferEmbeddedConsoleTags) as? Bool ?? false,
            sidebarBrowserModeRawValue: defaults.string(forKey: AppDefaultsKey.sidebarBrowserMode),
            libgmeTempo: shared.libgmeTempo,
            libgmeTempoEnabled: shared.libgmeTempoEnabled,
            libvgmTempo: shared.libvgmTempo,
            libvgmTempoEnabled: shared.libvgmTempoEnabled
        )
    }

    static func saveSessionState(
        playlist: [TrackItem],
        deferredPersistedValues: [String] = [],
        selectedTrackID: String?,
        currentTrackID: String?,
        rootPath: String?,
        selectedFolderPath: String?,
        librarySelectedFolderPath: String?,
        sidebarSearchText: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(playlist.map(\.persistedValue) + deferredPersistedValues, forKey: AppDefaultsKey.persistedPlaylistPaths)
        defaults.set(selectedTrackID, forKey: AppDefaultsKey.persistedSelectedTrackPath)
        defaults.set(currentTrackID, forKey: AppDefaultsKey.persistedCurrentTrackPath)
        defaults.set(rootPath, forKey: AppDefaultsKey.lastRootPath)
        defaults.set(selectedFolderPath, forKey: AppDefaultsKey.lastSelectedFolderPath)
        defaults.set(selectedFolderPath ?? librarySelectedFolderPath, forKey: AppDefaultsKey.lastLibrarySelectedFolderPath)
        defaults.set(sidebarSearchText, forKey: AppDefaultsKey.sidebarSearchText)
        defaults.removeObject(forKey: AppDefaultsKey.playlistSearchText)
    }

    static func savePlaybackPreferences(
        longPlayEnabled: Bool,
        playlistFollowsCursor: Bool,
        manualPreFadeSeconds: Int,
        unknownDurationSeconds: Int,
        endFadeEnabled: Bool,
        fadeSeconds: Int,
        fadedSkipEnabled: Bool,
        equalizerEnabled: Bool,
        equalizerBandGains: [Float],
        appVolume: Float,
        monoEnabled: Bool,
        randomPlaybackScopeRawValue: String,
        repeatModeRawValue: String,
        sidebarDoubleClickActionRawValue: String,
        databaseSidebarFontSize: CGFloat,
        databaseSidebarTextColor: String,
        databaseSidebarMonospaceFont: Bool,
        databaseSidebarDisclosureGapPoints: CGFloat,
        databaseSidebarChildIndentPoints: CGFloat,
        databaseSidebarHidesFileExtensions: Bool,
        playlistFontSize: CGFloat,
        playlistTextColor: String,
        playlistMonospaceFont: Bool,
        sidebarSystemMode: Bool,
        preferEmbeddedConsoleTags: Bool,
        sidebarBrowserModeRawValue: String,
        libgmeTempo: PlaybackTempo,
        libgmeTempoEnabled: Bool,
        libvgmTempo: PlaybackTempo,
        libvgmTempoEnabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        let shared = PlaybackPreferences(
            timing: PlaybackTimingPreferences(
                longPlaySeconds: manualPreFadeSeconds,
                unknownDurationSeconds: unknownDurationSeconds,
                fadeSeconds: fadeSeconds
            ),
            fadeEnabled: endFadeEnabled,
            equalizerEnabled: equalizerEnabled,
            equalizerBandGains: equalizerBandGains,
            outputVolume: appVolume,
            monoEnabled: monoEnabled,
            libgmeTempo: libgmeTempo,
            libgmeTempoEnabled: libgmeTempoEnabled,
            libvgmTempo: libvgmTempo,
            libvgmTempoEnabled: libvgmTempoEnabled
        )
        defaults.set(longPlayEnabled, forKey: AppDefaultsKey.longPlayEnabled)
        defaults.set(playlistFollowsCursor, forKey: AppDefaultsKey.playlistFollowsCursor)
        defaults.set(shared.timing.longPlaySeconds, forKey: AppDefaultsKey.manualPreFadeSeconds)
        defaults.set(shared.timing.unknownDurationSeconds, forKey: AppDefaultsKey.unknownDurationSeconds)
        defaults.set(shared.fadeEnabled, forKey: AppDefaultsKey.endFadeEnabled)
        defaults.set(shared.timing.fadeSeconds, forKey: AppDefaultsKey.fadeSeconds)
        defaults.set(fadedSkipEnabled, forKey: AppDefaultsKey.fadedSkipEnabled)
        defaults.set(shared.equalizer.enabled, forKey: AppDefaultsKey.equalizerEnabled)
        defaults.set(shared.equalizer.gainsDecibels.map(Double.init), forKey: AppDefaultsKey.equalizerBandGains)
        defaults.set(Double(shared.outputVolume), forKey: AppDefaultsKey.appVolume)
        defaults.set(shared.monoEnabled, forKey: AppDefaultsKey.monoEnabled)
        defaults.set(randomPlaybackScopeRawValue, forKey: AppDefaultsKey.randomPlaybackScope)
        defaults.set(repeatModeRawValue, forKey: AppDefaultsKey.repeatMode)
        defaults.set(sidebarDoubleClickActionRawValue, forKey: AppDefaultsKey.sidebarDoubleClickAction)
        defaults.set(Double(databaseSidebarFontSize), forKey: AppDefaultsKey.databaseSidebarFontSize)
        defaults.set(databaseSidebarTextColor, forKey: AppDefaultsKey.databaseSidebarTextColor)
        defaults.set(databaseSidebarMonospaceFont, forKey: AppDefaultsKey.databaseSidebarMonospaceFont)
        defaults.set(Double(databaseSidebarDisclosureGapPoints), forKey: AppDefaultsKey.databaseSidebarDisclosureGapPoints)
        defaults.set(Double(databaseSidebarChildIndentPoints), forKey: AppDefaultsKey.databaseSidebarChildIndentPoints)
        defaults.set(databaseSidebarHidesFileExtensions, forKey: AppDefaultsKey.databaseSidebarHidesFileExtensions)
        defaults.set(Double(playlistFontSize), forKey: AppDefaultsKey.playlistFontSize)
        defaults.set(playlistTextColor, forKey: AppDefaultsKey.playlistTextColor)
        defaults.set(playlistMonospaceFont, forKey: AppDefaultsKey.playlistMonospaceFont)
        defaults.set(sidebarSystemMode, forKey: AppDefaultsKey.sidebarSystemMode)
        defaults.set(preferEmbeddedConsoleTags, forKey: AppDefaultsKey.preferEmbeddedConsoleTags)
        defaults.set(sidebarBrowserModeRawValue, forKey: AppDefaultsKey.sidebarBrowserMode)
        defaults.set(shared.libgmeTempo.numerator, forKey: AppDefaultsKey.libgmeTempoNumerator)
        defaults.set(shared.libgmeTempo.denominator, forKey: AppDefaultsKey.libgmeTempoDenominator)
        defaults.set(shared.libgmeTempoEnabled, forKey: AppDefaultsKey.libgmeTempoEnabled)
        defaults.set(shared.libvgmTempo.numerator, forKey: AppDefaultsKey.libvgmTempoNumerator)
        defaults.set(shared.libvgmTempo.denominator, forKey: AppDefaultsKey.libvgmTempoDenominator)
        defaults.set(shared.libvgmTempoEnabled, forKey: AppDefaultsKey.libvgmTempoEnabled)
    }

    static func savePlaylistSortState(
        columnRawValue: String?,
        directionRawValue: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(columnRawValue, forKey: AppDefaultsKey.playlistSortColumn)
        defaults.set(directionRawValue, forKey: AppDefaultsKey.playlistSortDirection)
    }

    static func savePlaylistColumnState(
        order: [String]?,
        visibility: [String: Bool]?,
        widths: [String: Double]?,
        defaults: UserDefaults = .standard
    ) {
        if let order {
            defaults.set(order, forKey: AppDefaultsKey.playlistColumnOrder)
        }
        if let visibility {
            defaults.set(visibility, forKey: AppDefaultsKey.playlistColumnVisibility)
        }
        if let widths {
            defaults.set(widths, forKey: AppDefaultsKey.playlistColumnWidths)
        }
    }

    static func restorePlaylistColumnState(defaults: UserDefaults = .standard) -> RestoredPlaylistColumnState {
        RestoredPlaylistColumnState(
            order: defaults.stringArray(forKey: AppDefaultsKey.playlistColumnOrder) ?? [],
            visibility: defaults.dictionary(forKey: AppDefaultsKey.playlistColumnVisibility) as? [String: Bool] ?? [:],
            widths: defaults.dictionary(forKey: AppDefaultsKey.playlistColumnWidths) as? [String: Double] ?? [:]
        )
    }

    static func restoreSessionState(
        defaults: UserDefaults = .standard,
        supportedExtensions: Set<String>
    ) -> RestoredSessionState? {
        let values = defaults.stringArray(forKey: AppDefaultsKey.persistedPlaylistPaths) ?? []
        let restoredValues = values.prefix(maximumRestoredPlaylistTracks)
        let deferredValues = Array(values.dropFirst(restoredValues.count))
        let tracks = restoredValues
            .compactMap(TrackItem.fromPersistedValue)
            .filter { supportedExtensions.contains($0.playablePathExtension) }

        guard !tracks.isEmpty else { return nil }

        return RestoredSessionState(
            tracks: tracks,
            deferredTrackCount: max(0, values.count - restoredValues.count),
            deferredPersistedValues: deferredValues,
            selectedTrackID: defaults.string(forKey: AppDefaultsKey.persistedSelectedTrackPath),
            currentTrackID: defaults.string(forKey: AppDefaultsKey.persistedCurrentTrackPath),
            lastSelectedFolderPath: defaults.string(forKey: AppDefaultsKey.lastSelectedFolderPath),
            lastLibrarySelectedFolderPath: defaults.string(forKey: AppDefaultsKey.lastLibrarySelectedFolderPath)
        )
    }

    static func restoreStartupState(
        defaults: UserDefaults = .standard,
        supportedExtensions: Set<String>
    ) -> RestoredAppStartupState {
        RestoredAppStartupState(
            playbackPreferences: restorePlaybackPreferences(defaults: defaults),
            sessionState: restoreSessionState(
                defaults: defaults,
                supportedExtensions: supportedExtensions
            ),
            playlistColumnState: restorePlaylistColumnState(defaults: defaults),
            sidebarSearchText: lastSidebarSearchText(defaults: defaults),
            lastRootPath: lastRootPath(defaults: defaults),
            lastLibrarySelectedFolderPath: lastLibrarySelectedFolderPath(defaults: defaults)
        )
    }

    static func saveActiveLibraryContext(
        rootPath: String,
        selectedLibraryFolderPath: String?,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(rootPath, forKey: AppDefaultsKey.lastRootPath)
        defaults.set(selectedLibraryFolderPath, forKey: AppDefaultsKey.lastLibrarySelectedFolderPath)
    }

    static func lastLibrarySelectedFolderPath(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: AppDefaultsKey.lastLibrarySelectedFolderPath)
    }

    static func lastRootPath(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: AppDefaultsKey.lastRootPath)
    }

    static func lastSidebarSearchText(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: AppDefaultsKey.sidebarSearchText) ?? ""
    }

}
