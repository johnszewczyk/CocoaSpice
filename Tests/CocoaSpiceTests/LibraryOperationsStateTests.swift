import AppKit
import Foundation
import Testing
@testable import CocoaSpice

@MainActor
@Test func libraryScanRequestQueuePreservesFIFOOrderAndRootIdentity() {
    let firstRoot = LibraryScanRoot(id: 11, path: "/Music/First", isEnabled: true, displayOrder: 0, lastScanStartedAt: nil, lastScanCompletedAt: nil, lastScanTrackCount: 0, lastScanError: nil)
    let secondRoot = LibraryScanRoot(id: 22, path: "/Music/Second", isEnabled: true, displayOrder: 1, lastScanStartedAt: nil, lastScanCompletedAt: nil, lastScanTrackCount: 0, lastScanError: nil)
    let queue = LibraryScanRequestQueue()

    queue.enqueue(roots: [secondRoot, firstRoot], mode: .newScan)
    queue.enqueue(roots: [firstRoot], mode: .incremental)

    #expect(queue.count == 2)
    let firstRequest = queue.dequeue()
    #expect(firstRequest?.rootIDs == [22, 11])
    #expect(firstRequest?.mode == .newScan)
    let secondRequest = queue.dequeue()
    #expect(secondRequest?.rootIDs == [11])
    #expect(secondRequest?.mode == .incremental)
    #expect(queue.count == 0)
}

@MainActor
@Test func libraryOperationTaskStateInvalidatesFinishedAndCancelledWork() {
    let state = LibraryOperationsState()
    let firstGeneration = state.beginTask()
    #expect(state.isCurrentTask(firstGeneration))
    state.finishTask(generation: firstGeneration)
    #expect(!state.isCurrentTask(firstGeneration))
    let secondGeneration = state.beginTask()
    #expect(state.isCurrentTask(secondGeneration))
    state.cancelActiveTask()
    #expect(!state.isCurrentTask(secondGeneration))
}

@MainActor
@Test func latestTaskOwnerCancelsReplacedAndCompletedWork() {
    let owner = LatestTaskOwner()
    let firstGeneration = owner.begin()
    #expect(owner.isActive)
    let task = Task { @MainActor in await Task.yield() }
    owner.install(task, generation: firstGeneration)
    let secondGeneration = owner.begin()
    #expect(task.isCancelled)
    #expect(!owner.isCurrent(firstGeneration))
    #expect(owner.isCurrent(secondGeneration))
    owner.finish(generation: secondGeneration)
    #expect(!owner.isCurrent(secondGeneration))
    #expect(!owner.isActive)
}

@MainActor
@Test func latestTaskOwnerCanRemainCurrentWhileCancellationSettles() {
    let owner = LatestTaskOwner()
    let generation = owner.begin()
    let task = Task { @MainActor in
        _ = try? await Task.sleep(for: .seconds(10))
    }
    owner.install(task, generation: generation)

    owner.requestCancellation()

    #expect(task.isCancelled)
    #expect(owner.isCurrent(generation))
    #expect(owner.isActive)
    owner.finish(generation: generation)
    #expect(!owner.isCurrent(generation))
    #expect(!owner.isActive)
}

@MainActor
@Test func playbackRequestStateInvalidatesCancelledRequestsAndTracksPendingPlayback() {
    let state = PlaybackRequestState()
    let track = TrackItem(url: URL(fileURLWithPath: "/tmp/theme.spc"))
    let generation = state.begin(track: track)
    #expect(state.pendingTrack == track)
    #expect(state.isCurrent(generation))
    state.cancel()
    #expect(state.pendingTrack == nil)
    #expect(!state.isCurrent(generation))
}

@MainActor
@Test func libraryOperationStateClampsScanProgressAndPrefersLinkTests() {
    let state = LibraryOperationsState()
    state.scanCurrentPath = "/Music/JoshW"
    state.scanCurrentFile = "Game.tar.zst"
    state.setScanProgress(rootID: 1, current: 120, total: 100)
    #expect(state.scanProgressByRootID[1] == LibraryScanProgress(current: 100, total: 100))
    #expect(state.operationProgress == LibraryScanProgress(current: 100, total: 100))
    state.linkTestProgress = LibraryScanProgress(current: 4, total: 9)
    #expect(state.operationProgress == LibraryScanProgress(current: 4, total: 9))
    state.clearScanProgress(rootID: 1)
    #expect(state.scanProgressByRootID.isEmpty)
    state.resetScanProgress()
    #expect(state.scanProgressByRootID.isEmpty)
    #expect(state.scanCurrentPath == nil)
    #expect(state.scanCurrentFile == nil)
}

@Test func databaseFileFolderDisclosureIgnoresRangeSelectionModifiers() {
    #expect(DatabaseFileSidebarInteraction.allowsFolderDisclosure(modifierFlags: []))
    #expect(!DatabaseFileSidebarInteraction.allowsFolderDisclosure(modifierFlags: .shift))
    #expect(!DatabaseFileSidebarInteraction.allowsFolderDisclosure(modifierFlags: .command))
    #expect(!DatabaseFileSidebarInteraction.allowsFolderDisclosure(modifierFlags: [.shift, .command]))
}
