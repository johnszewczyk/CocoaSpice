import AppKit
import Foundation

enum AppDefaultsKey {
    static let lastRootPath = "SPCBoy.lastRootPath"
    static let lastSelectedFolderPath = "SPCBoy.lastSelectedFolderPath"
    static let lastLibrarySelectedFolderPath = "SPCBoy.lastLibrarySelectedFolderPath"
    static let sidebarSearchText = "SPCBoy.sidebarSearchText"
    static let playlistSearchText = "SPCBoy.playlistSearchText"
    static let longPlayEnabled = "SPCBoy.longPlayEnabled"
    static let manualPreFadeSeconds = "SPCBoy.manualPreFadeSeconds"
    static let spectrumGradientStartColor = "SPCBoy.spectrumGradientStartColor"
    static let spectrumGradientEndColor = "SPCBoy.spectrumGradientEndColor"
    static let spectrumPeakColor = "SPCBoy.spectrumPeakColor"
    static let sidebarDoubleClickAction = "SPCBoy.sidebarDoubleClickAction"
    static let playlistFollowsCursor = "SPCBoy.playlistFollowsCursor"
    static let lastAudioExportDirectoryPath = "SPCBoy.lastAudioExportDirectoryPath"
    static let playlistSortColumn = "SPCBoy.playlistSortColumn"
    static let playlistSortDirection = "SPCBoy.playlistSortDirection"
    static let persistedPlaylistPaths = "SPCBoy.persistedPlaylistPaths"
    static let persistedSelectedTrackPath = "SPCBoy.persistedSelectedTrackPath"
    static let persistedCurrentTrackPath = "SPCBoy.persistedCurrentTrackPath"
    static let playlistColumnOrder = "SPCBoy.playlistColumnOrder"
    static let playlistColumnVisibility = "SPCBoy.playlistColumnVisibility"
    static let playlistColumnWidths = "SPCBoy.playlistColumnWidths"
}

struct RestoredPlaybackPreferences {
    let longPlayEnabled: Bool
    let playlistFollowsCursor: Bool
    let manualPreFadeSeconds: Int?
    let spectrumGradientStartColor: String?
    let spectrumGradientEndColor: String?
    let spectrumPeakColor: String?
    let sidebarDoubleClickActionRawValue: String?
    let lastAudioExportDirectoryPath: String?
    let playlistSortColumnRawValue: String?
    let playlistSortDirectionRawValue: String?
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

enum AppSessionPersistence {
    static func restorePlaybackPreferences(defaults: UserDefaults = .standard) -> RestoredPlaybackPreferences {
        return RestoredPlaybackPreferences(
            longPlayEnabled: defaults.bool(forKey: AppDefaultsKey.longPlayEnabled),
            playlistFollowsCursor: defaults.object(forKey: AppDefaultsKey.playlistFollowsCursor) as? Bool ?? false,
            manualPreFadeSeconds: {
                let storedUnifiedPreFade = defaults.integer(forKey: AppDefaultsKey.manualPreFadeSeconds)
                return storedUnifiedPreFade > 0 ? storedUnifiedPreFade : nil
            }(),
            spectrumGradientStartColor: defaults.string(forKey: AppDefaultsKey.spectrumGradientStartColor),
            spectrumGradientEndColor: defaults.string(forKey: AppDefaultsKey.spectrumGradientEndColor),
            spectrumPeakColor: defaults.string(forKey: AppDefaultsKey.spectrumPeakColor),
            sidebarDoubleClickActionRawValue: defaults.string(forKey: AppDefaultsKey.sidebarDoubleClickAction),
            lastAudioExportDirectoryPath: defaults.string(forKey: AppDefaultsKey.lastAudioExportDirectoryPath),
            playlistSortColumnRawValue: defaults.string(forKey: AppDefaultsKey.playlistSortColumn),
            playlistSortDirectionRawValue: defaults.string(forKey: AppDefaultsKey.playlistSortDirection)
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
        playlistSearchText: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(playlist.map(\.persistedValue), forKey: AppDefaultsKey.persistedPlaylistPaths)
        defaults.set(selectedTrackID, forKey: AppDefaultsKey.persistedSelectedTrackPath)
        defaults.set(currentTrackID, forKey: AppDefaultsKey.persistedCurrentTrackPath)
        defaults.set(rootPath, forKey: AppDefaultsKey.lastRootPath)
        defaults.set(selectedFolderPath, forKey: AppDefaultsKey.lastSelectedFolderPath)
        defaults.set(selectedFolderPath ?? librarySelectedFolderPath, forKey: AppDefaultsKey.lastLibrarySelectedFolderPath)
        defaults.set(sidebarSearchText, forKey: AppDefaultsKey.sidebarSearchText)
        defaults.set(playlistSearchText, forKey: AppDefaultsKey.playlistSearchText)
    }

    static func savePlaybackPreferences(
        longPlayEnabled: Bool,
        playlistFollowsCursor: Bool,
        manualPreFadeSeconds: Int,
        spectrumGradientStartColor: NSColor,
        spectrumGradientEndColor: NSColor,
        spectrumPeakColor: NSColor,
        sidebarDoubleClickActionRawValue: String,
        lastAudioExportDirectoryPath: String?,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(longPlayEnabled, forKey: AppDefaultsKey.longPlayEnabled)
        defaults.set(playlistFollowsCursor, forKey: AppDefaultsKey.playlistFollowsCursor)
        defaults.set(manualPreFadeSeconds, forKey: AppDefaultsKey.manualPreFadeSeconds)
        defaults.set(serializedColor(spectrumGradientStartColor), forKey: AppDefaultsKey.spectrumGradientStartColor)
        defaults.set(serializedColor(spectrumGradientEndColor), forKey: AppDefaultsKey.spectrumGradientEndColor)
        defaults.set(serializedColor(spectrumPeakColor), forKey: AppDefaultsKey.spectrumPeakColor)
        defaults.set(sidebarDoubleClickActionRawValue, forKey: AppDefaultsKey.sidebarDoubleClickAction)
        defaults.set(lastAudioExportDirectoryPath, forKey: AppDefaultsKey.lastAudioExportDirectoryPath)
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
            .filter { supportedExtensions.contains($0.url.pathExtension.lowercased()) }

        guard !tracks.isEmpty else { return nil }

        return RestoredSessionState(
            tracks: tracks,
            selectedTrackID: defaults.string(forKey: AppDefaultsKey.persistedSelectedTrackPath),
            currentTrackID: defaults.string(forKey: AppDefaultsKey.persistedCurrentTrackPath),
            lastSelectedFolderPath: defaults.string(forKey: AppDefaultsKey.lastSelectedFolderPath),
            lastLibrarySelectedFolderPath: defaults.string(forKey: AppDefaultsKey.lastLibrarySelectedFolderPath)
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

    static func lastPlaylistSearchText(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: AppDefaultsKey.playlistSearchText) ?? ""
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
