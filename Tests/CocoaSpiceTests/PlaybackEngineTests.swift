import AppKit
import C2SF
import Foundation
import Testing
@testable import CocoaSpice

// Retain historic test names while production code uses the neutral registry.
private typealias GMEFormatSupport = PlaybackFormatRegistry

@Test @MainActor func spectrumAnalyzerUsesConfigurableTenTwentyAndFortyBandLayouts() {
    let model = ToolbarSpectrumModel()
    #expect(model.bandCount == 10)
    model.configure(bandCount: 20)
    #expect(model.bandCount == 20)
    #expect(model.levels.count == 20)
    model.configure(bandCount: 40)
    #expect(model.bandCount == 40)
    #expect(model.capLevels.count == 40)
    #expect(SpectrumBandCount.clamped(999) == 40)
}

@Test @MainActor func spectrumStopsAnimatingWhenHidden() {
    let model = ToolbarSpectrumModel()
    model.isVisible = true
    model.setAnimating(true)
    #expect(model.isAnimating)

    model.isVisible = false
    #expect(!model.isAnimating)
}

@Test @MainActor func spectrumIgnoresInFlightLevelsWhenStoppedOrHidden() {
    let model = ToolbarSpectrumModel()
    let levels = Array(repeating: Float(0.75), count: model.bandCount)

    model.update(with: levels)
    #expect(model.targetLevels.allSatisfy { $0 == 0 })

    model.isVisible = true
    model.setAnimating(true)
    model.update(with: levels)
    #expect(model.targetLevels.allSatisfy { $0 == 0.75 })

    model.setAnimating(false)
    model.update(with: levels)
    #expect(model.targetLevels.allSatisfy { $0 == 0 })
}

@Test func playbackBackendRoutesVGMFamilyToLibVGM() {
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "spc") == .gme)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "nsf") == .gme)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "vgm") == .libvgm)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "vgz") == .libvgm)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "gym") == .libvgm)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "s98") == .libvgm)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "gsf") == .highlyComplete)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "minigsf") == .highlyComplete)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "ssf") == .highlyTheoretical)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "minissf") == .highlyTheoretical)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "usf") == .lazyUSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "miniusf") == .lazyUSF)
}

@Test func decoderRegistryDeclaresPlaylistEnumerationCapability() {
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "PSF") == .playPSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "minipsf") == .playPSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "PSF2") == .playPSF)
    #expect(GMEFormatSupport.playbackBackend(forPathExtension: "minipsf2") == .playPSF)
    #expect(!GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "psf2"))
    #expect(!GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "psf"))
    #expect(!GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "mini2sf"))
    #expect(!GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "spc"))
    #expect(GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "nsf"))
    #expect(GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "adx"))
    #expect(GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "xa"))
    #expect(GMEFormatSupport.requiresTrackEnumeration(forPathExtension: "GENH"))
    #expect(GMEFormatSupport.module(forPathExtension: "minipsf")?.pluginID == "play-psf1")
    #expect(GMEFormatSupport.module(forPathExtension: "minipsf2")?.pluginID == "play-psf2")
    #expect(GMEFormatSupport.module(forPathExtension: "minissf")?.pluginID == "highly-theoretical")
    #expect(GMEFormatSupport.module(forPathExtension: "spc")?.pluginID == "gme")
    #expect(GMEFormatSupport.module(forPathExtension: "nsf")?.pluginID == "gme-multitrack")
    #expect(GMEFormatSupport.module(forPathExtension: "psf")?.archiveMaterialization == .completeSet)
    #expect(GMEFormatSupport.module(forPathExtension: "psf2")?.archiveMaterialization == .completeSet)
    #expect(GMEFormatSupport.module(forPathExtension: "minissf")?.archiveMaterialization == .completeSet)
    #expect(GMEFormatSupport.module(forPathExtension: "psf")?.scanArchiveMaterialization == .selectedEntry)
    #expect(GMEFormatSupport.module(forPathExtension: "psf2")?.scanArchiveMaterialization == .selectedEntry)
    #expect(GMEFormatSupport.module(forPathExtension: "miniusf")?.archiveMaterialization == .completeSetWithLazyUSFAliases)
    #expect(GMEFormatSupport.module(forPathExtension: "adx")?.archiveMaterialization == .selectedEntry)
    let expectedGMEConcurrency = min(
        3,
        max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    )
    #expect(GMEFormatSupport.module(forPathExtension: "spc")?.scanInspectionConcurrency == expectedGMEConcurrency)
    #expect(GMEFormatSupport.module(forPathExtension: "minipsf2")?.scanInspectionConcurrency == 1)
    #expect(GMEFormatSupport.modules.count == 15)
    #expect(GMEFormatSupport.module(forPathExtension: "PSF")?.pluginID == "play-psf1")
    #expect(GMEFormatSupport.module(forPathExtension: "PSF2")?.pluginID == "play-psf2")
    #expect(GMEFormatSupport.module(forPathExtension: "MINISSF")?.pluginID == "highly-theoretical")
    #expect(GMEFormatSupport.module(forPathExtension: "XA")?.pluginID == "vgmstream")
    #expect(GMEFormatSupport.module(forPathExtension: "GENH")?.pluginID == "vgmstream")

    let registeredExtensionCount = GMEFormatSupport.modules.reduce(0) {
        $0 + $1.supportedExtensions.count
    }
    #expect(GMEFormatSupport.supportedExtensions.count == registeredExtensionCount)
}

@Test func archiveInspectionPolicyPreservesDependencySets() {
    #expect(GMEFormatSupport.archiveMaterializationForInspection(
        entryPaths: ["01.spc", "02.spc"]
    ) == .selectedEntry)
    #expect(GMEFormatSupport.archiveMaterializationForInspection(
        entryPaths: ["01.minipsf2", "02.psf2"]
    ) == .completeSet)
    #expect(GMEFormatSupport.archiveMaterializationForInspection(
        entryPaths: ["01.spc", "02.miniusf"]
    ) == .completeSetWithLazyUSFAliases)
}

@Test func archiveScanPolicyUsesSelectedPSFFamilyMembers() {
    #expect(GMEFormatSupport.scanArchiveMaterializationForInspection(
        entryPaths: ["01.minipsf2", "02.psf2"]
    ) == .selectedEntry)
    #expect(GMEFormatSupport.scanArchiveMaterializationForInspection(
        entryPaths: ["01.spc", "02.miniusf"]
    ) == .selectedEntry)
}

@Test func playlistMetadataPreparationBatchesArchiveMembersByContainer() {
    let firstArchive = URL(fileURLWithPath: "/music/first.7z")
    let secondArchive = URL(fileURLWithPath: "/music/second.zip")
    let batches = PlaybackInspection.archiveBatches(for: [
        TrackItem(archiveURL: firstArchive, entryPath: "01.spc"),
        TrackItem(archiveURL: firstArchive, entryPath: "01.spc", trackIndex: 1, trackCount: 2),
        TrackItem(url: URL(fileURLWithPath: "/music/direct.spc")),
        TrackItem(archiveURL: firstArchive, entryPath: "02.spc"),
        TrackItem(archiveURL: secondArchive, entryPath: "03.spc")
    ])

    #expect(batches == [
        PlaylistMetadataArchiveBatch(
            archiveURL: firstArchive.standardizedFileURL,
            entryPaths: ["01.spc", "02.spc"]
        ),
        PlaylistMetadataArchiveBatch(
            archiveURL: secondArchive.standardizedFileURL,
            entryPaths: ["03.spc"]
        )
    ])
    #expect(PlaybackInspection.metadataWorkerLimit == 2)
}

@Test func playlistMetadataPreparationUsesOneMaterializedSPCSet() async throws {
    let archiveURL = URL(fileURLWithPath: "/Users/john/Downloads/audio/JoshW/SPC/0-9/3 Ninjas Kick Back (1994-11)(Malibu)(Sony Imagesoft)[SNES].7z")
    guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
    let entries = try ZipArchiveSupport.listPlayableEntries(
        in: archiveURL,
        supportedExtensions: ["spc"]
    )
    let jobs = PlaybackInspection.prepareMetadataInspectionJobs(
        tracks: entries.map {
            TrackItem(archiveURL: archiveURL, entryPath: $0.entryPath)
        }
    )

    #expect(jobs.count == entries.count)
    #expect(jobs.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
    let selectionDirectories = Set(jobs.compactMap { job in
        job.fileURL.pathComponents.first(where: { $0.hasPrefix("selection-") })
    })
    #expect(selectionDirectories.count == 1)
    if let firstJob = jobs.first {
        let metadata = try await PlaybackInspection.inspectMetadata(
            track: firstJob.track,
            fileURL: firstJob.fileURL
        )
        #expect(metadata.playLengthMs > 0)
    }
}

@Test func frameAccountingUsesSuppliedOutputFrames() {
    #expect(PlaybackFrameAccounting.positionFrames(
        sessionStartFrame: 44_100,
        framesSupplied: 22_050
    ) == 66_150)
    #expect(PlaybackFrameAccounting.positionSeconds(
        sessionStartFrame: 44_100,
        framesSupplied: 22_050,
        sampleRate: 44_100
    ) == 1.5)
}

@Test func frameAccountingDoesNotMoveBackwardsForNegativeSupply() {
    #expect(PlaybackFrameAccounting.positionFrames(
        sessionStartFrame: 44_100,
        framesSupplied: -1
    ) == 44_100)
}

@Test func frameAccountingPreservesTheAudiblePositionAcrossABufferReset() {
    // Long Play reconfiguration clears the PCM ring. The new generation's
    // counter begins at zero, while its session anchor remains the last
    // audible frame from the preceding generation.
    let audibleFrameBeforeReconfigure: Int64 = 137_812
    #expect(PlaybackFrameAccounting.positionFrames(
        sessionStartFrame: audibleFrameBeforeReconfigure,
        framesSupplied: 0
    ) == audibleFrameBeforeReconfigure)
}

@Test func nativeCompletionWaitsForBufferedFramesToDrain() {
    #expect(!PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: true,
        plannedFrameCount: nil,
        framesSupplied: 10_000,
        bufferedFrames: 512
    ))
    #expect(PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: true,
        plannedFrameCount: nil,
        framesSupplied: 10_000,
        bufferedFrames: 0
    ))
}

@Test func fixedDurationCompletionUsesPlannedFramesAndDrain() {
    #expect(!PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: false,
        plannedFrameCount: 44_100,
        framesSupplied: 44_100,
        bufferedFrames: 256
    ))
    #expect(PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: false,
        plannedFrameCount: 44_100,
        framesSupplied: 44_100,
        bufferedFrames: 0
    ))
    #expect(!PlaybackCompletionPolicy.shouldFinish(
        reachedDecoderEnd: false,
        plannedFrameCount: 44_100,
        framesSupplied: 44_099,
        bufferedFrames: 0
    ))
}

@Test func realtimeRingBufferPreservesStereoFramesAndCapacity() throws {
    let ringBuffer = try RealtimePCMFrameRingBuffer(capacityFrames: 3)
    let inputLeft: [Float] = [0.1, 0.2, 0.3, 0.4]
    let inputRight: [Float] = [1.1, 1.2, 1.3, 1.4]

    let written = inputLeft.withUnsafeBufferPointer { left in
        inputRight.withUnsafeBufferPointer { right in
            ringBuffer.write(left: left, right: right)
        }
    }

    #expect(written == 3)
    #expect(ringBuffer.bufferedFrames == 3)

    var outputLeft = Array(repeating: Float.zero, count: 3)
    var outputRight = Array(repeating: Float.zero, count: 3)
    let read = outputLeft.withUnsafeMutableBufferPointer { left in
        outputRight.withUnsafeMutableBufferPointer { right in
            ringBuffer.read(left: left, right: right)
        }
    }

    #expect(read == 3)
    #expect(outputLeft == [0.1, 0.2, 0.3])
    #expect(outputRight == [1.1, 1.2, 1.3])
    #expect(ringBuffer.bufferedFrames == 0)
}

@Test func realtimeRingBufferWrapsAfterReadAndClear() throws {
    let ringBuffer = try RealtimePCMFrameRingBuffer(capacityFrames: 3)
    let firstLeft: [Float] = [1, 2]
    let firstRight: [Float] = [11, 12]
    _ = firstLeft.withUnsafeBufferPointer { left in
        firstRight.withUnsafeBufferPointer { right in
            ringBuffer.write(left: left, right: right)
        }
    }

    var discardedLeft = Array(repeating: Float.zero, count: 2)
    var discardedRight = Array(repeating: Float.zero, count: 2)
    _ = discardedLeft.withUnsafeMutableBufferPointer { left in
        discardedRight.withUnsafeMutableBufferPointer { right in
            ringBuffer.read(left: left, right: right)
        }
    }

    let secondLeft: [Float] = [3, 4, 5]
    let secondRight: [Float] = [13, 14, 15]
    _ = secondLeft.withUnsafeBufferPointer { left in
        secondRight.withUnsafeBufferPointer { right in
            ringBuffer.write(left: left, right: right)
        }
    }

    var outputLeft = Array(repeating: Float.zero, count: 3)
    var outputRight = Array(repeating: Float.zero, count: 3)
    _ = outputLeft.withUnsafeMutableBufferPointer { left in
        outputRight.withUnsafeMutableBufferPointer { right in
            ringBuffer.read(left: left, right: right)
        }
    }

    #expect(outputLeft == [3, 4, 5])
    #expect(outputRight == [13, 14, 15])

    ringBuffer.clear()
    #expect(ringBuffer.bufferedFrames == 0)
    #expect(ringBuffer.framesRead == 0)
    #expect(ringBuffer.framesRequested == 0)
    #expect(ringBuffer.underrunCount == 0)
}

@Test func realtimeRingBufferTracksOutputDemandAndUnderruns() throws {
    let ringBuffer = try RealtimePCMFrameRingBuffer(capacityFrames: 2)
    let input: [Float] = [1, 2]
    _ = input.withUnsafeBufferPointer { values in
        ringBuffer.write(left: values, right: values)
    }

    var outputLeft = Array(repeating: Float.zero, count: 3)
    var outputRight = Array(repeating: Float.zero, count: 3)
    _ = outputLeft.withUnsafeMutableBufferPointer { left in
        outputRight.withUnsafeMutableBufferPointer { right in
            ringBuffer.read(left: left, right: right)
        }
    }

    #expect(ringBuffer.framesRequested == 3)
    #expect(ringBuffer.framesRead == 2)
    #expect(ringBuffer.underrunCount == 1)
}

@Test func rapidQueueNavigationCanAdvanceFromPendingTrack() {
    let first = TrackItem(url: URL(fileURLWithPath: "/tmp/one.spc"))
    let second = TrackItem(url: URL(fileURLWithPath: "/tmp/two.spc"))
    let third = TrackItem(url: URL(fileURLWithPath: "/tmp/three.spc"))
    let playlist = [first, second, third]

    let nextFromFirst = QueueTransportNavigation.adjacentTrack(
        from: first,
        in: playlist,
        direction: .next,
        wraps: true
    )
    let nextFromPending = QueueTransportNavigation.adjacentTrack(
        from: nextFromFirst,
        in: playlist,
        direction: .next,
        wraps: true
    )

    #expect(nextFromFirst == second)
    #expect(nextFromPending == third)
}

@Test func completionAdvancesWithinTheCurrentQueueWithoutWrapping() {
    let first = TrackItem(url: URL(fileURLWithPath: "/tmp/one.spc"))
    let second = TrackItem(url: URL(fileURLWithPath: "/tmp/two.spc"))
    let third = TrackItem(url: URL(fileURLWithPath: "/tmp/three.spc"))
    let playlist = [first, second, third]

    #expect(QueueTransportNavigation.completionAdvanceTarget(
        currentTrack: first,
        playlist: playlist
    ) == second)
    #expect(QueueTransportNavigation.completionAdvanceTarget(
        currentTrack: third,
        playlist: playlist
    ) == nil)
}

@Test func completionStartsAtHeadWhenAReplacementQueueDoesNotContainPlayingTrack() {
    let oldTrack = TrackItem(url: URL(fileURLWithPath: "/tmp/old.spc"))
    let replacementFirst = TrackItem(url: URL(fileURLWithPath: "/tmp/new-one.spc"))
    let replacementSecond = TrackItem(url: URL(fileURLWithPath: "/tmp/new-two.spc"))

    #expect(QueueTransportNavigation.completionAdvanceTarget(
        currentTrack: oldTrack,
        playlist: [replacementFirst, replacementSecond]
    ) == replacementFirst)
    #expect(QueueTransportNavigation.completionAdvanceTarget(
        currentTrack: oldTrack,
        playlist: []
    ) == nil)
}
