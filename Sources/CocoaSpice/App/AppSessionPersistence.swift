import AppKit
import Foundation

enum AppDefaultsKey {
    static let lastRootPath = "CocoaSpice.lastRootPath"
    static let lastSelectedFolderPath = "CocoaSpice.lastSelectedFolderPath"
    static let lastLibrarySelectedFolderPath = "CocoaSpice.lastLibrarySelectedFolderPath"
    static let sidebarSearchText = "CocoaSpice.sidebarSearchText"
    static let playlistSearchText = "CocoaSpice.playlistSearchText"
    static let longPlayEnabled = "CocoaSpice.longPlayEnabled"
    static let manualPreFadeSeconds = "CocoaSpice.manualPreFadeSeconds"
    static let endFadeEnabled = "CocoaSpice.endFadeEnabled"
    static let spectrumGradientStartColor = "CocoaSpice.spectrumGradientStartColor"
    static let spectrumGradientEndColor = "CocoaSpice.spectrumGradientEndColor"
    static let spectrumPeakColor = "CocoaSpice.spectrumPeakColor"
    static let spectrumEnabled = "CocoaSpice.spectrumEnabled"
    static let spectrumBandCount = "CocoaSpice.spectrumBandCount"
    static let equalizerEnabled = "CocoaSpice.equalizerEnabled"
    static let equalizerBandGains = "CocoaSpice.equalizerBandGains"
    static let appVolume = "CocoaSpice.appVolume"
    static let randomPlaybackScope = "CocoaSpice.randomPlaybackScope"
    static let repeatMode = "CocoaSpice.repeatMode"
    static let sidebarDoubleClickAction = "CocoaSpice.sidebarDoubleClickAction"
    static let playlistFollowsCursor = "CocoaSpice.playlistFollowsCursor"
    static let lastAudioExportDirectoryPath = "CocoaSpice.lastAudioExportDirectoryPath"
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
    static let playlistMonospaceFont = "CocoaSpice.playlistMonospaceFont"
    static let sidebarSystemMode = "CocoaSpice.sidebarSystemMode"
    static let sidebarBrowserMode = "CocoaSpice.sidebarBrowserMode"
}

struct RestoredPlaybackPreferences {
    let longPlayEnabled: Bool
    let playlistFollowsCursor: Bool
    let manualPreFadeSeconds: Int?
    let endFadeEnabled: Bool
    let spectrumGradientStartColor: String?
    let spectrumGradientEndColor: String?
    let spectrumPeakColor: String?
    let spectrumEnabled: Bool
    let spectrumBandCount: Int
    let equalizerEnabled: Bool
    let equalizerBandGains: [Double]?
    let appVolume: Double
    let randomPlaybackScopeRawValue: String?
    let repeatModeRawValue: String?
    let sidebarDoubleClickActionRawValue: String?
    let lastAudioExportDirectoryPath: String?
    let playlistSortColumnRawValue: String?
    let playlistSortDirectionRawValue: String?
    let databaseSidebarFontSize: Double?
    let databaseSidebarTextColor: String?
    let databaseSidebarMonospaceFont: Bool
    let playlistMonospaceFont: Bool
    let sidebarSystemMode: Bool
    let sidebarBrowserModeRawValue: String?
}

struct RestoredSessionState {
    let tracks: [TrackItem]
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
    private static let legacyPrefix = "SPCBoy."

    static func migrateLegacyPreferences(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "CocoaSpice.fastLibraryScan")
        defaults.removeObject(forKey: "SPCBoy.fastLibraryScan")
        let keys = [
            "lastRootPath", "lastSelectedFolderPath", "lastLibrarySelectedFolderPath",
            "sidebarSearchText", "playlistSearchText", "longPlayEnabled", "manualPreFadeSeconds", "endFadeEnabled",
            "spectrumGradientStartColor", "spectrumGradientEndColor", "spectrumPeakColor", "spectrumEnabled", "spectrumBandCount", "equalizerEnabled", "equalizerBandGains", "appVolume", "randomPlaybackScope", "repeatMode",
            "sidebarDoubleClickAction", "playlistFollowsCursor", "lastAudioExportDirectoryPath",
            "playlistSortColumn", "playlistSortDirection", "persistedPlaylistPaths",
            "persistedSelectedTrackPath", "persistedCurrentTrackPath", "playlistColumnOrder",
            "playlistColumnVisibility", "playlistColumnWidths", "databaseSidebarFontSize", "databaseSidebarTextColor", "databaseSidebarMonospaceFont", "playlistMonospaceFont", "sidebarSystemMode", "sidebarBrowserMode"
        ]

        for suffix in keys {
            let legacyKey = legacyPrefix + suffix
            let currentKey = "CocoaSpice." + suffix
            guard defaults.object(forKey: currentKey) == nil,
                  let legacyValue = defaults.object(forKey: legacyKey) else {
                continue
            }
            defaults.set(legacyValue, forKey: currentKey)
            defaults.removeObject(forKey: legacyKey)
        }
    }

    static func restorePlaybackPreferences(defaults: UserDefaults = .standard) -> RestoredPlaybackPreferences {
        return RestoredPlaybackPreferences(
            longPlayEnabled: defaults.bool(forKey: AppDefaultsKey.longPlayEnabled),
            playlistFollowsCursor: defaults.object(forKey: AppDefaultsKey.playlistFollowsCursor) as? Bool ?? false,
            manualPreFadeSeconds: {
                let storedUnifiedPreFade = defaults.integer(forKey: AppDefaultsKey.manualPreFadeSeconds)
                return storedUnifiedPreFade > 0 ? storedUnifiedPreFade : nil
            }(),
            endFadeEnabled: defaults.object(forKey: AppDefaultsKey.endFadeEnabled) as? Bool ?? true,
            spectrumGradientStartColor: defaults.string(forKey: AppDefaultsKey.spectrumGradientStartColor),
            spectrumGradientEndColor: defaults.string(forKey: AppDefaultsKey.spectrumGradientEndColor),
            spectrumPeakColor: defaults.string(forKey: AppDefaultsKey.spectrumPeakColor),
            spectrumEnabled: defaults.object(forKey: AppDefaultsKey.spectrumEnabled) as? Bool ?? true,
            spectrumBandCount: SpectrumBandCount.clamped(defaults.integer(forKey: AppDefaultsKey.spectrumBandCount)),
            equalizerEnabled: defaults.object(forKey: AppDefaultsKey.equalizerEnabled) as? Bool ?? false,
            equalizerBandGains: (defaults.array(forKey: AppDefaultsKey.equalizerBandGains) as? [NSNumber])?.map(\.doubleValue),
            appVolume: defaults.object(forKey: AppDefaultsKey.appVolume) as? Double ?? 1,
            randomPlaybackScopeRawValue: defaults.string(forKey: AppDefaultsKey.randomPlaybackScope),
            repeatModeRawValue: defaults.string(forKey: AppDefaultsKey.repeatMode),
            sidebarDoubleClickActionRawValue: defaults.string(forKey: AppDefaultsKey.sidebarDoubleClickAction),
            lastAudioExportDirectoryPath: defaults.string(forKey: AppDefaultsKey.lastAudioExportDirectoryPath),
            playlistSortColumnRawValue: defaults.string(forKey: AppDefaultsKey.playlistSortColumn),
            playlistSortDirectionRawValue: defaults.string(forKey: AppDefaultsKey.playlistSortDirection),
            databaseSidebarFontSize: defaults.object(forKey: AppDefaultsKey.databaseSidebarFontSize) as? Double,
            databaseSidebarTextColor: defaults.string(forKey: AppDefaultsKey.databaseSidebarTextColor),
            databaseSidebarMonospaceFont: defaults.object(forKey: AppDefaultsKey.databaseSidebarMonospaceFont) as? Bool ?? false,
            playlistMonospaceFont: defaults.object(forKey: AppDefaultsKey.playlistMonospaceFont) as? Bool ?? false,
            sidebarSystemMode: defaults.object(forKey: AppDefaultsKey.sidebarSystemMode) as? Bool ?? false,
            sidebarBrowserModeRawValue: defaults.string(forKey: AppDefaultsKey.sidebarBrowserMode)
        )
    }

    static func saveSessionState(
        playlist: [TrackItem],
        selectedTrackID: String?,
        currentTrackID: String?,
        rootPath: String?,
        selectedFolderPath: String?,
        librarySelectedFolderPath: String?,
        sidebarSearchText: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(playlist.map(\.persistedValue), forKey: AppDefaultsKey.persistedPlaylistPaths)
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
        endFadeEnabled: Bool,
        spectrumGradientStartColor: NSColor,
        spectrumGradientEndColor: NSColor,
        spectrumPeakColor: NSColor,
        spectrumEnabled: Bool,
        spectrumBandCount: Int,
        equalizerEnabled: Bool,
        equalizerBandGains: [Float],
        appVolume: Float,
        randomPlaybackScopeRawValue: String,
        repeatModeRawValue: String,
        sidebarDoubleClickActionRawValue: String,
        lastAudioExportDirectoryPath: String?,
        databaseSidebarFontSize: CGFloat,
        databaseSidebarTextColor: String,
        databaseSidebarMonospaceFont: Bool,
        playlistMonospaceFont: Bool,
        sidebarSystemMode: Bool,
        sidebarBrowserModeRawValue: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(longPlayEnabled, forKey: AppDefaultsKey.longPlayEnabled)
        defaults.set(playlistFollowsCursor, forKey: AppDefaultsKey.playlistFollowsCursor)
        defaults.set(manualPreFadeSeconds, forKey: AppDefaultsKey.manualPreFadeSeconds)
        defaults.set(endFadeEnabled, forKey: AppDefaultsKey.endFadeEnabled)
        defaults.set(serializedColor(spectrumGradientStartColor), forKey: AppDefaultsKey.spectrumGradientStartColor)
        defaults.set(serializedColor(spectrumGradientEndColor), forKey: AppDefaultsKey.spectrumGradientEndColor)
        defaults.set(serializedColor(spectrumPeakColor), forKey: AppDefaultsKey.spectrumPeakColor)
        defaults.set(spectrumEnabled, forKey: AppDefaultsKey.spectrumEnabled)
        defaults.set(SpectrumBandCount.clamped(spectrumBandCount), forKey: AppDefaultsKey.spectrumBandCount)
        defaults.set(equalizerEnabled, forKey: AppDefaultsKey.equalizerEnabled)
        defaults.set(equalizerBandGains.map(Double.init), forKey: AppDefaultsKey.equalizerBandGains)
        defaults.set(Double(AudioOutputVolume.clamped(appVolume)), forKey: AppDefaultsKey.appVolume)
        defaults.set(randomPlaybackScopeRawValue, forKey: AppDefaultsKey.randomPlaybackScope)
        defaults.set(repeatModeRawValue, forKey: AppDefaultsKey.repeatMode)
        defaults.set(sidebarDoubleClickActionRawValue, forKey: AppDefaultsKey.sidebarDoubleClickAction)
        defaults.set(lastAudioExportDirectoryPath, forKey: AppDefaultsKey.lastAudioExportDirectoryPath)
        defaults.set(Double(databaseSidebarFontSize), forKey: AppDefaultsKey.databaseSidebarFontSize)
        defaults.set(databaseSidebarTextColor, forKey: AppDefaultsKey.databaseSidebarTextColor)
        defaults.set(databaseSidebarMonospaceFont, forKey: AppDefaultsKey.databaseSidebarMonospaceFont)
        defaults.set(playlistMonospaceFont, forKey: AppDefaultsKey.playlistMonospaceFont)
        defaults.set(sidebarSystemMode, forKey: AppDefaultsKey.sidebarSystemMode)
        defaults.set(sidebarBrowserModeRawValue, forKey: AppDefaultsKey.sidebarBrowserMode)
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
        fileManager: FileManager = .default,
        supportedExtensions: Set<String>
    ) -> RestoredSessionState? {
        let values = defaults.stringArray(forKey: AppDefaultsKey.persistedPlaylistPaths) ?? []
        let tracks = values
            .compactMap(TrackItem.fromPersistedValue)
            .filter { fileManager.fileExists(atPath: $0.url.path) }
            .filter { supportedExtensions.contains($0.playablePathExtension) }

        guard !tracks.isEmpty else { return nil }

        return RestoredSessionState(
            tracks: tracks,
            selectedTrackID: defaults.string(forKey: AppDefaultsKey.persistedSelectedTrackPath),
            currentTrackID: defaults.string(forKey: AppDefaultsKey.persistedCurrentTrackPath),
            lastSelectedFolderPath: defaults.string(forKey: AppDefaultsKey.lastSelectedFolderPath),
            lastLibrarySelectedFolderPath: defaults.string(forKey: AppDefaultsKey.lastLibrarySelectedFolderPath)
        )
    }

    static func restoreStartupState(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        supportedExtensions: Set<String>
    ) -> RestoredAppStartupState {
        RestoredAppStartupState(
            playbackPreferences: restorePlaybackPreferences(defaults: defaults),
            sessionState: restoreSessionState(
                defaults: defaults,
                fileManager: fileManager,
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

    static func serializedColor(_ color: NSColor) -> String? {
        guard let converted = color.usingColorSpace(.deviceRGB) else { return nil }
        return [
            converted.redComponent,
            converted.greenComponent,
            converted.blueComponent,
            converted.alphaComponent
        ]
        .map { String(format: "%.6f", $0) }
        .joined(separator: ",")
    }

    static func deserializeColor(_ value: String) -> NSColor? {
        let parts = value.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return NSColor(
            red: parts[0],
            green: parts[1],
            blue: parts[2],
            alpha: parts[3]
        )
    }
}
