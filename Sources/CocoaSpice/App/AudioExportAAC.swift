import AppKit
import Foundation

struct AudioExportRequest: Sendable { let track: TrackItem; let metadata: TrackMetadata; let plan: PlaybackPlan; let outputURL: URL }
struct AudioExportBatchResult: Sendable { let exportedCount: Int; let outputDirectory: URL }
struct AudioExportProgressSnapshot: Sendable {
    enum Phase: Sendable { case preparing, exporting, completed, cancelled, failed }
    let phase: Phase; let title: String; let outputDirectoryPath: String; let currentFileName: String?
    let completedFiles: Int; let totalFiles: Int; let currentFileProgress: Double?; let batchProgress: Double
    var remainingFiles: Int { max(totalFiles - completedFiles, 0) }
}
enum AudioExportError: LocalizedError { case unavailable; var errorDescription: String? { "AAC export will return when VGMBoy exposes its shared export endpoint." } }
enum AudioExportAACService {
    @MainActor static func makeDestinationFolderPanel(defaultDirectory: URL?) -> NSOpenPanel {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.directoryURL = defaultDirectory; return panel
    }
    static func buildRequests(tracks: [TrackItem], cachedMetadata: [String: TrackMetadata], outputDirectory: URL, longPlayEnabled: Bool, manualPreFadeSeconds: Int, fadeSeconds: Int) async throws -> [AudioExportRequest] {
        tracks.map { track in
            let metadata = cachedMetadata[track.id] ?? TrackMetadata(game: "", song: "", system: "", author: "", comment: "", introLengthMs: 0, loopLengthMs: 0, playLengthMs: 0, fadeLengthMs: 0)
            let plan = PlaybackTimingPolicy.playbackPlan(metadata: metadata, trackPathExtension: track.playablePathExtension, longPlayEnabled: longPlayEnabled, manualPreFadeSeconds: manualPreFadeSeconds, fadeSeconds: fadeSeconds)
            return AudioExportRequest(track: track, metadata: metadata, plan: plan, outputURL: outputDirectory.appendingPathComponent(track.displayName).appendingPathExtension("m4a"))
        }
    }
    static func export(requests: [AudioExportRequest], progress: @escaping @Sendable (AudioExportProgressSnapshot) -> Void) async throws -> AudioExportBatchResult { throw AudioExportError.unavailable }
}
