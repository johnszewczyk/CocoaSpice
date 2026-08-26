import Foundation
import FrontendPreferencesCore
import VGMBoyEndpointCore
import VGMBoyKit

/// Versioned, skin-neutral capability declaration for CocoaSpice itself.
/// It is an in-process Swift boundary today; a future WebKit bridge can expose
/// the same Codable values without importing SwiftUI or AppKit.
enum CocoaSpiceFrontendProtocol {
    static let version = 1
}

enum CocoaSpiceFrontendFeature: String, Codable, CaseIterable, Sendable {
    case options
    case mainPlayback = "main_playback"
}

struct CocoaSpiceFrontendSurface: Codable, Equatable, Sendable {
    let version: Int
    let features: Set<CocoaSpiceFrontendFeature>
    let vgmboyEndpointSurface: VGMBoyEndpointSurface

    func supports(_ feature: CocoaSpiceFrontendFeature) -> Bool {
        features.contains(feature)
    }

    static let v1 = CocoaSpiceFrontendSurface(
        version: CocoaSpiceFrontendProtocol.version,
        features: Set(CocoaSpiceFrontendFeature.allCases),
        vgmboyEndpointSurface: .v1
    )
}

/// Everything a skin needs to render CocoaSpice's existing Options panels.
/// It contains user preferences and presentation values only: never catalog
/// rows, scanner state, decoder metadata, or a playback path.
struct CocoaSpiceOptionsSnapshot: Codable, Equatable, Sendable {
    let version: Int
    let manifest: FrontendOptionsManifest
    let frontendInterface: FrontendInterfacePreferences
    let longPlayEnabled: Bool
    let manualPreFadeSeconds: Int
    let unknownDurationSeconds: Int
    let endFadeEnabled: Bool
    let fadeSeconds: Int
    let fadedSkipEnabled: Bool
    let equalizerEnabled: Bool
    let equalizerBandGains: [Float]
    let appVolume: Float
    let monoEnabled: Bool
    let playlistFollowsCursor: Bool
    let doubleClickEnqueues: Bool
    let interfaceFontSize: Double
    let interfaceTextColor: String
    let interfaceMonospaceFont: Bool
    let sidebarSystemMode: Bool
    let preferFoldersOverMetadata: Bool
    let sidebarHidesFileExtensions: Bool
    let sidebarDisclosureGapPoints: Double
    let sidebarChildIndentPoints: Double
    let catalogPath: String
    let catalogStatus: String?
    let cacheEnabled: Bool
    let cacheLimitBytes: Int64
    let cacheSummary: String
    let isClearingCache: Bool
    let aacExportDirectory: String
    let diagnostics: PlaybackDiagnosticsSnapshot
    let libgmeTempo: PlaybackTempo
    let libgmeTempoEnabled: Bool
    let libvgmTempo: PlaybackTempo
    let libvgmTempoEnabled: Bool
    let columnAutoSize: Bool
}

/// Typed mutations accepted by the Options contract. A skin supplies a file
/// path for catalog selection; only the native CocoaSpice shell decides how a
/// user chooses that path (currently `NSOpenPanel`).
enum CocoaSpiceOptionsCommand: Codable, Equatable, Sendable {
    case setAutoResizeAnimationEnabled(Bool)
    case setAutoResizeAnimationMilliseconds(Int)
    case setSelectionAnimationEnabled(Bool)
    case setSelectionAnimationMilliseconds(Int)
    case setColumnAutoSize(Bool)
    case setWindowAlwaysOnTop(role: FrontendWindowRole, enabled: Bool)
    case setLongPlayEnabled(Bool)
    case setManualPreFadeSeconds(Int)
    case setUnknownDurationSeconds(Int)
    case setEndFadeEnabled(Bool)
    case setFadeSeconds(Int)
    case setFadedSkipEnabled(Bool)
    case setEqualizerEnabled(Bool)
    case setEqualizerBand(index: Int, gain: Float)
    case resetEqualizer
    case setAppVolume(Float)
    case setMonoEnabled(Bool)
    case setPlaylistFollowsCursor(Bool)
    case setDoubleClickEnqueues(Bool)
    case setInterfaceFontSize(Double)
    case setInterfaceTextColor(String)
    case setInterfaceMonospaceFont(Bool)
    case setSidebarSystemMode(Bool)
    case setPreferFoldersOverMetadata(Bool)
    case setSidebarHidesFileExtensions(Bool)
    case setSidebarDisclosureGapPoints(Double)
    case setSidebarChildIndentPoints(Double)
    case setLibGmeTempo(PlaybackTempo)
    case setLibGmeTempoEnabled(Bool)
    case setLibVgmTempo(PlaybackTempo)
    case setLibVgmTempoEnabled(Bool)
    case reloadCatalog
    case useDefaultCatalog
    case selectCatalog(path: String)
    case refreshCacheSummary
    case setCacheEnabled(Bool)
    case setCacheLimitBytes(Int64)
    case clearCache
    case selectAACExportDirectory(path: String)
}

/// Adapter from a future skin to the established CocoaSpice model. It keeps
/// the model's behavior authoritative while giving another renderer a compact
/// query/command surface instead of direct SwiftUI bindings.
@MainActor
final class CocoaSpiceOptionsControlSurface {
    let surface = CocoaSpiceFrontendSurface.v1
    private unowned let model: PlayerViewModel

    init(model: PlayerViewModel) {
        self.model = model
    }

    func snapshot() -> CocoaSpiceOptionsSnapshot {
        CocoaSpiceOptionsSnapshot(
            version: surface.version,
            manifest: .v1,
            frontendInterface: model.frontendPreferences.value,
            longPlayEnabled: model.longPlayEnabled,
            manualPreFadeSeconds: model.manualPreFadeSeconds,
            unknownDurationSeconds: model.unknownDurationSeconds,
            endFadeEnabled: model.endFadeEnabled,
            fadeSeconds: model.configuredFadeSeconds,
            fadedSkipEnabled: model.fadedSkipEnabled,
            equalizerEnabled: model.equalizerEnabled,
            equalizerBandGains: model.equalizerBandGains,
            appVolume: model.appVolume,
            monoEnabled: model.monoEnabled,
            playlistFollowsCursor: model.playlistFollowsCursor,
            doubleClickEnqueues: model.sidebarDoubleClickAction == .enqueue,
            interfaceFontSize: Double(model.interfaceFontSize),
            interfaceTextColor: model.interfaceTextColor.rawValue,
            interfaceMonospaceFont: model.interfaceMonospaceFont,
            sidebarSystemMode: model.sidebarSystemMode,
            preferFoldersOverMetadata: model.preferFoldersOverMetadata,
            sidebarHidesFileExtensions: model.databaseSidebarHidesFileExtensions,
            sidebarDisclosureGapPoints: Double(model.databaseSidebarDisclosureGapPoints),
            sidebarChildIndentPoints: Double(model.databaseSidebarChildIndentPoints),
            catalogPath: model.configuredLibraryDatabasePath,
            catalogStatus: model.libraryDatabaseLocationStatus,
            cacheEnabled: model.archiveCachePolicy.isEnabled,
            cacheLimitBytes: model.archiveCachePolicy.maximumBytes,
            cacheSummary: model.archiveCacheSummaryText,
            isClearingCache: model.isClearingArchiveCache,
            aacExportDirectory: model.aacExportDirectoryPath,
            diagnostics: model.playbackDiagnostics,
            libgmeTempo: model.libgmeTempo,
            libgmeTempoEnabled: model.libgmeTempoEnabled,
            libvgmTempo: model.libvgmTempo,
            libvgmTempoEnabled: model.libvgmTempoEnabled,
            columnAutoSize: model.columnAutoSizeEnabled
        )
    }

    func perform(_ command: CocoaSpiceOptionsCommand) {
        switch command {
        case .setAutoResizeAnimationEnabled(let enabled):
            model.setAutoResizeAnimationEnabled(enabled)
        case .setAutoResizeAnimationMilliseconds(let milliseconds):
            model.setAutoResizeAnimationMilliseconds(milliseconds)
        case .setSelectionAnimationEnabled(let enabled):
            model.setSelectionAnimationEnabled(enabled)
        case .setSelectionAnimationMilliseconds(let milliseconds):
            model.setSelectionAnimationMilliseconds(milliseconds)
        case .setColumnAutoSize(let enabled):
            model.setColumnAutoSizeEnabled(enabled)
        case .setWindowAlwaysOnTop(let role, let enabled):
            switch role {
            case .main: model.setMainWindowAlwaysOnTop(enabled)
            case .settings: model.setSettingsWindowAlwaysOnTop(enabled)
            case .about: break
            }
        case .setLongPlayEnabled(let enabled):
            if model.longPlayEnabled != enabled { model.toggleLongPlayEnabled() }
        case .setManualPreFadeSeconds(let seconds):
            model.manualPreFadeSeconds = max(30, seconds)
            model.handleManualPlaySecondsChanged()
        case .setUnknownDurationSeconds(let seconds):
            model.setUnknownDurationSeconds(seconds)
        case .setEndFadeEnabled(let enabled):
            model.setEndFadeEnabled(enabled)
        case .setFadeSeconds(let seconds):
            model.setFadeSeconds(seconds)
        case .setFadedSkipEnabled(let enabled):
            model.setFadedSkipEnabled(enabled)
        case .setEqualizerEnabled(let enabled):
            model.setEqualizerEnabled(enabled)
        case .setEqualizerBand(let index, let gain):
            model.setEqualizerBandGain(gain, at: index)
        case .resetEqualizer:
            model.resetEqualizer()
        case .setAppVolume(let volume):
            model.setAppVolume(volume)
        case .setMonoEnabled(let enabled):
            model.setMonoEnabled(enabled)
        case .setPlaylistFollowsCursor(let enabled):
            model.setPlaylistFollowsCursorEnabled(enabled)
        case .setDoubleClickEnqueues(let enabled):
            model.setSidebarDoubleClickAction(enabled ? .enqueue : .playNow)
        case .setInterfaceFontSize(let size):
            model.setDatabaseSidebarFontSize(CGFloat(size))
        case .setInterfaceTextColor(let rawValue):
            guard let color = PlayerViewModel.DatabaseSidebarTextColor(rawValue: rawValue) else { return }
            model.setDatabaseSidebarTextColor(color)
        case .setInterfaceMonospaceFont(let enabled):
            model.setDatabaseSidebarMonospaceFont(enabled)
        case .setSidebarSystemMode(let enabled):
            model.setSidebarSystemMode(enabled)
        case .setPreferFoldersOverMetadata(let enabled):
            model.setPreferFoldersOverMetadata(enabled)
        case .setSidebarHidesFileExtensions(let enabled):
            model.setDatabaseSidebarHidesFileExtensions(enabled)
        case .setSidebarDisclosureGapPoints(let points):
            model.setDatabaseSidebarDisclosureGapPoints(CGFloat(points))
        case .setSidebarChildIndentPoints(let points):
            model.setDatabaseSidebarChildIndentPoints(CGFloat(points))
        case .setLibGmeTempo(let tempo):
            model.setLibGmeTempo(tempo)
        case .setLibGmeTempoEnabled(let enabled):
            model.setLibGmeTempoEnabled(enabled)
        case .setLibVgmTempo(let tempo):
            model.setLibVgmTempo(tempo)
        case .setLibVgmTempoEnabled(let enabled):
            model.setLibVgmTempoEnabled(enabled)
        case .reloadCatalog:
            model.reloadLibrary()
        case .useDefaultCatalog:
            model.useDefaultLibraryDatabase()
        case .selectCatalog(let path):
            model.selectLibraryDatabase(at: URL(fileURLWithPath: path))
        case .refreshCacheSummary:
            model.refreshArchiveCacheSummary()
        case .setCacheEnabled(let enabled):
            model.setArchiveCacheEnabled(enabled)
        case .setCacheLimitBytes(let bytes):
            model.setArchiveCacheLimitBytes(bytes)
        case .clearCache:
            model.clearArchiveCache()
        case .selectAACExportDirectory(let path):
            model.setAACExportDirectory(URL(fileURLWithPath: path, isDirectory: true))
        }
    }
}

/// Read-only main playback presentation for a non-native skin. Track display
/// strings come from CocoaSpice's read-only catalog/playlist presentation;
/// no decoder inspection is requested here.
struct CocoaSpiceMainPlaybackSnapshot: Codable, Equatable, Sendable {
    let version: Int
    let isLoading: Bool
    let isPlaying: Bool
    let elapsedSeconds: Double
    let durationSeconds: Int
    let sliderUpperBound: Double
    let songTitle: String
    let gameTitle: String
    let systemText: String
    let authorText: String
    let statusText: String
    let longPlayEnabled: Bool
    let currentTrackSupportsLongPlay: Bool
    let repeatMode: String
    let randomPlaybackScope: String
    let playlistTrackCount: Int
}

enum CocoaSpiceMainPlaybackCommand: Codable, Equatable, Sendable {
    case togglePlayback
    case play
    case pause
    case next
    case previous
    case seek(seconds: Double)
    case setLongPlayEnabled(Bool)
    case cycleRepeatMode
    case cycleRandomPlaybackScope
}

/// Adapter for the transport and playback-policy controls visible in the
/// native main toolbar. Playlist membership and sidebar selection remain a
/// separate future contract because they carry table-selection semantics.
@MainActor
final class CocoaSpiceMainPlaybackControlSurface {
    let surface = CocoaSpiceFrontendSurface.v1
    private unowned let model: PlayerViewModel

    init(model: PlayerViewModel) {
        self.model = model
    }

    func snapshot() -> CocoaSpiceMainPlaybackSnapshot {
        CocoaSpiceMainPlaybackSnapshot(
            version: surface.version,
            isLoading: model.isLoading,
            isPlaying: model.isPlaying,
            elapsedSeconds: model.displayedElapsedSeconds,
            durationSeconds: model.totalPlaybackSeconds,
            sliderUpperBound: model.sliderRangeUpperBound,
            songTitle: model.currentSongTitle,
            gameTitle: model.currentGameTitle,
            systemText: model.statusSystemText,
            authorText: model.statusAuthorText,
            statusText: model.statusText,
            longPlayEnabled: model.longPlayEnabled,
            currentTrackSupportsLongPlay: model.currentTrackSupportsLongPlay,
            repeatMode: model.repeatMode.rawValue,
            randomPlaybackScope: model.randomPlaybackScope.rawValue,
            playlistTrackCount: model.playlist.count
        )
    }

    func perform(_ command: CocoaSpiceMainPlaybackCommand) {
        switch command {
        case .togglePlayback:
            model.togglePlayback()
        case .play:
            model.resumePlayback()
        case .pause:
            model.pausePlayback()
        case .next:
            model.playNext()
        case .previous:
            model.playPrevious()
        case .seek(let seconds):
            guard seconds.isFinite else { return }
            model.beginSeek()
            model.seekPreviewSeconds = min(max(0, seconds), model.sliderRangeUpperBound)
            model.completeSeek()
        case .setLongPlayEnabled(let enabled):
            if model.longPlayEnabled != enabled { model.toggleLongPlayEnabled() }
        case .cycleRepeatMode:
            model.cycleRepeatMode()
        case .cycleRandomPlaybackScope:
            model.cycleRandomPlaybackScope()
        }
    }
}
