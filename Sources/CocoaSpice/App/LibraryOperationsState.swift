import Foundation
import Observation

struct LibraryScanProgress: Sendable, Equatable {
    let current: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

/// Observable state owned by library maintenance rather than playback or
/// playlist editing. `PlayerViewModel` currently forwards this state while
/// library actions migrate behind their own controller boundary.
@MainActor
@Observable
final class LibraryOperationsState {
    @ObservationIgnored private let taskOwner = LatestTaskOwner()

    var scanRoots: [LibraryScanRoot] = []
    var status: String?
    var cleanRootIDs: Set<Int64> = []
    var trimmedRootIDs: Set<Int64> = []
    var scanInProgress = false
    var scanIsCancelling = false
    var forceScan = false
    var scanProgressByRootID: [Int64: LibraryScanProgress] = [:]
    var scanCurrentPath: String?
    var scanCurrentFile: String?
    var linkTestProgress: LibraryScanProgress?
    var linkTestCurrentPath: String?

    var archiveCacheSummaryText = "Calculating…"
    var isClearingArchiveCache = false

    var deadLinkSummaryText = "Calculating…"
    var deadLinkCount = 0
    var databaseEntryCount = 0
    var unlinkedDatabaseEntryCount = 0
    var isDeletingDeadLinks = false
    var isLoadingDatabaseSidebar = false

    var operationProgress: LibraryScanProgress? {
        linkTestProgress ?? scanProgressByRootID.values.first
    }

    func resetScanProgress() {
        scanProgressByRootID = [:]
        scanCurrentPath = nil
        scanCurrentFile = nil
    }

    func clearScanProgress(rootID: Int64) {
        scanProgressByRootID[rootID] = nil
    }

    func setScanProgress(rootID: Int64, current: Int, total: Int) {
        let safeTotal = max(total, 0)
        scanProgressByRootID[rootID] = LibraryScanProgress(
            current: min(max(current, 0), safeTotal),
            total: safeTotal
        )
    }

    /// Starts a replacement library-maintenance operation and returns the
    /// generation that its callbacks must carry before changing UI state.
    func beginTask() -> Int {
        taskOwner.begin()
    }

    func installTask(_ task: Task<Void, Never>, generation: Int) {
        taskOwner.install(task, generation: generation)
    }

    func isCurrentTask(_ generation: Int) -> Bool {
        taskOwner.isCurrent(generation)
    }

    func finishTask(generation: Int) {
        taskOwner.finish(generation: generation)
    }

    func cancelActiveTask() {
        taskOwner.cancel()
    }

    func requestActiveTaskCancellation() {
        taskOwner.requestCancellation()
    }
}
