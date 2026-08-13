import Foundation
import MediaScannerKit

typealias ScanPipelineError = MediaScannerKit.ScanPipelineError
typealias ScanActivity = MediaScannerKit.ScanActivity
typealias ScanLifecyclePhase = MediaScannerKit.ScanLifecyclePhase
typealias ScanOperationTimeout = MediaScannerKit.ScanOperationTimeout

struct ScanPipelineExecutor: Sendable {
    let pluginRegistry: ScanPluginRegistry
    let handlerRegistry: ScanPluginHandlerRegistry
    let archiveProvider: any ScanArchiveProvider
    let inspectionScheduler: ScanResourceScheduler

    init(
        pluginRegistry: ScanPluginRegistry = ScanCoreHandlers.registry,
        handlerRegistry: ScanPluginHandlerRegistry = ScanCoreHandlers.handlers,
        archiveProvider: (any ScanArchiveProvider)? = nil,
        scheduler: ScanResourceScheduler? = nil
    ) {
        self.pluginRegistry = pluginRegistry
        self.handlerRegistry = handlerRegistry
        // Archive tools and metadata decoders have different bottlenecks.
        // They deliberately receive independent lanes: a slow extractor no
        // longer occupies an inspection permit, while callers/tests that pass
        // one scheduler retain their explicit shared-budget behavior.
        let archiveScheduler = scheduler ?? ScanResourceScheduler(
            permits: max(1, ProcessInfo.processInfo.activeProcessorCount)
        )
        self.inspectionScheduler = scheduler ?? ScanResourceScheduler(
            permits: max(1, ProcessInfo.processInfo.activeProcessorCount)
        )
        self.archiveProvider = archiveProvider ?? ZipScanArchiveProvider(
            registry: pluginRegistry,
            scheduler: archiveScheduler
        )
    }

    func process(
        plan: ScanPlan,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in },
        activity: @escaping @Sendable (Int, Int, ScanActivity) -> Void = { _, _, _ in },
        issue: @escaping @Sendable (ScanFailure) -> Void = { _ in },
        persist: @escaping @Sendable ([ScanPipelineResult]) async throws -> Void
    ) async throws -> ScanResultAccumulator {
        let accumulator = ScanResultAccumulator(discovered: plan.count)
        let cursor = ScanPlanCursor(count: plan.candidates.count)
        let completionCounter = ScanCompletionCounter()
        let workerCount = min(
            ZipArchiveSupport.archiveProcessConcurrency,
            max(1, plan.candidates.count)
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask {
                    while let index = cursor.take() {
                        try Task.checkCancellation()
                        let candidate = plan.candidates[index]
                        let results = await self.process(candidate) { phase, detail in
                            activity(
                                completionCounter.current(),
                                plan.count,
                                ScanActivity(candidate: candidate, phase: phase, detail: detail)
                            )
                        }
                        try Task.checkCancellation()
                        // A complete loose source or complete archive is the
                        // durable checkpoint unit. The database still batches
                        // prepared writes internally, but one savepoint covers
                        // the whole source so resume can never observe half an
                        // archive after a process exit.
                        activity(
                            completionCounter.current(),
                            plan.count,
                            ScanActivity(
                                candidate: candidate,
                                phase: .persistence,
                                detail: "Checkpointing scan results…"
                            )
                        )
                        let acceptedResults: [ScanPipelineResult]
                        do {
                            try await persist(results)
                            acceptedResults = results
                        } catch {
                            // A disk/database failure belongs to this item. It must not
                            // cancel unrelated validation work.
                            acceptedResults = results.map { $0.persistenceFailure(message: error.localizedDescription) }
                        }
                        for acceptedResult in acceptedResults {
                            try await accumulator.accept(acceptedResult)
                            if case .failure(let failure) = acceptedResult {
                                issue(failure)
                            }
                        }
                        let identityDescription = candidate.identity.archiveEntry.map {
                            "\(candidate.identity.path)#\($0)"
                        } ?? candidate.identity.path
                        let completed = completionCounter.increment()
                        progress(completed, plan.count, "Completed \(identityDescription)")
                    }
                }
            }
            try await group.waitForAll()
        }
        try Task.checkCancellation()
        return accumulator
    }

    func process(
        _ candidate: ScanCandidate,
        activity: @escaping @Sendable (ScanLifecyclePhase, String) -> Void = { _, _ in }
    ) async -> [ScanPipelineResult] {
        do {
            if ZipArchiveSupport.canHandle(candidate.sourceURL), candidate.identity.archiveEntry == nil {
                return await processArchive(candidate, activity: activity)
            }
            if let archiveEntry = candidate.identity.archiveEntry {
                activity(.materialization, "Extracting \(candidate.identityDescription)…")
                let materializedURL = try await materialize(candidate, archiveEntry: archiveEntry)
                activity(.inspection, "Inspecting \(candidate.identityDescription)…")
                return [try await processFile(candidate, fileURL: materializedURL)]
            }
            let fingerprintedCandidate = await ScanSourceContentSignature.enrich(candidate)
            activity(.inspection, "Inspecting \(fingerprintedCandidate.identityDescription)…")
            return [try await processFile(fingerprintedCandidate)]
        } catch is CancellationError {
            return [failure(candidate, stage: .metadata, message: "Cancelled")]
        } catch {
            return [failure(candidate, stage: .metadata, message: error.localizedDescription)]
        }
    }

    private func processArchive(
        _ candidate: ScanCandidate,
        activity: @escaping @Sendable (ScanLifecyclePhase, String) -> Void
    ) async -> [ScanPipelineResult] {
        do {
            activity(.archiveListing, "Listing \(candidate.sourceURL.lastPathComponent)…")
            let archiveListing = try await ScanOperationTimeout.run(
                kind: .archiveListing,
                description: "listing \(candidate.sourceURL.lastPathComponent)"
            ) {
                try await archiveProvider.listMembers(
                    in: candidate.sourceURL,
                    supportedExtensions: pluginRegistry.supportedExtensions
                )
            }
            let members = archiveListing.members
            let completedCandidate = ScanCandidate(
                identity: candidate.identity,
                fingerprint: ScanFingerprint(
                    fileSize: candidate.fingerprint.fileSize,
                    modifiedAt: candidate.fingerprint.modifiedAt,
                    contentSignature: archiveListing.scanSignature
                ),
                sourceURL: candidate.sourceURL,
                route: candidate.route
            )

            var results: [ScanPipelineResult] = []
            results.reserveCapacity(members.count)
            guard !members.isEmpty else {
                return [.archiveCompleted(await ArchiveScanSignature.enrich(completedCandidate))]
            }
            let memberCandidates = members.map { member in
                ScanCandidate(
                    identity: ScanItemIdentity(
                        rootID: candidate.identity.rootID,
                        path: member.archiveURL.path,
                        archiveEntry: member.entryPath
                    ),
                    fingerprint: member.fingerprint,
                    sourceURL: member.archiveURL,
                    route: member.route
                )
            }
            if memberCandidates.allSatisfy({ $0.route?.usesDeferredSingleTrackMetadata == true }) {
                results.append(contentsOf: memberCandidates.compactMap { candidate in
                    candidate.route.map { .success(candidate, Self.catalogInspection(route: $0)) }
                })
                results.append(.archiveCompleted(await ArchiveScanSignature.enrich(completedCandidate)))
                return results
            }
            guard let materializationPolicy = PlaybackFormatRegistry.scanArchiveMaterializationForInspection(
                entryPaths: members.map(\.entryPath)
            ) else {
                throw ZipArchiveSupport.ArchiveError.invalidEntryPath(
                    members.first?.entryPath ?? ""
                )
            }
            let materializedRoot: URL
            do {
                activity(.materialization, "Extracting \(members.count) playable member\(members.count == 1 ? "" : "s") from \(candidate.sourceURL.lastPathComponent)…")
                switch materializationPolicy {
                case .selectedEntry:
                    materializedRoot = try await ScanOperationTimeout.run(
                        kind: .archiveExtraction,
                        description: "extracting playable members from \(candidate.sourceURL.lastPathComponent)"
                    ) {
                        try await archiveProvider.materializeEntriesForScan(
                            archiveURL: candidate.sourceURL,
                            entryPaths: members.map(\.entryPath)
                        )
                    }
                case .completeSet, .completeSetWithLazyUSFAliases:
                    materializedRoot = try await ScanOperationTimeout.run(
                        kind: .archiveExtraction,
                        description: "extracting dependency set \(candidate.sourceURL.lastPathComponent)"
                    ) {
                        try await archiveProvider.materializeArchiveForScan(at: candidate.sourceURL)
                    }
                }
            } catch is CancellationError {
                return memberCandidates.map {
                    failure($0, stage: .archiveExtraction, message: "Cancelled")
                }
            } catch {
                return memberCandidates.map {
                    failure($0, stage: .archiveExtraction, message: error.localizedDescription)
                }
            }

            if materializationPolicy == .completeSetWithLazyUSFAliases {
                do {
                    try ZipArchiveSupport.prepareLazyUSFDependencies(in: materializedRoot)
                } catch {
                    await archiveProvider.discardScanMaterialization(at: materializedRoot)
                    return memberCandidates.map {
                        failure($0, stage: .archiveExtraction, message: error.localizedDescription)
                    }
                }
            }
            if members.contains(where: { $0.route?.formatExtension == "txtp" }) {
                do {
                    try ZipArchiveSupport.prepareTXTPDependencies(in: materializedRoot)
                } catch {
                    await archiveProvider.discardScanMaterialization(at: materializedRoot)
                    return memberCandidates.map {
                        failure($0, stage: .archiveExtraction, message: error.localizedDescription)
                    }
                }
            }

            let memberCursor = ScanPlanCursor(count: members.count)
            let memberWorkerCount = min(
                ZipArchiveSupport.archiveProcessConcurrency,
                members.count
            )
            let memberCompletionCounter = ScanCompletionCounter()
            activity(.inspection, "Inspecting 0 / \(members.count) members in \(candidate.sourceURL.lastPathComponent)…")
            var orderedResults = Array<ScanPipelineResult?>(repeating: nil, count: members.count)
            await withTaskGroup(of: (Int, ScanPipelineResult).self) { group in
                for _ in 0..<memberWorkerCount {
                    guard let index = memberCursor.take() else { break }
                    group.addTask {
                        let result = await self.processMaterializedArchiveMember(
                            member: members[index],
                            candidate: memberCandidates[index],
                            materializedRoot: materializedRoot
                        )
                        let completed = memberCompletionCounter.increment()
                        if completed == 1 || completed == members.count || completed.isMultiple(of: 25) {
                            activity(.inspection, "Inspecting \(completed) / \(members.count) members in \(candidate.sourceURL.lastPathComponent)…")
                        }
                        return (index, result)
                    }
                }

                while let (index, result) = await group.next() {
                    orderedResults[index] = result
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        continue
                    }
                    guard let nextIndex = memberCursor.take() else { continue }
                    group.addTask {
                        let result = await self.processMaterializedArchiveMember(
                            member: members[nextIndex],
                            candidate: memberCandidates[nextIndex],
                            materializedRoot: materializedRoot
                        )
                        let completed = memberCompletionCounter.increment()
                        if completed == members.count || completed.isMultiple(of: 25) {
                            activity(.inspection, "Inspecting \(completed) / \(members.count) members in \(candidate.sourceURL.lastPathComponent)…")
                        }
                        return (nextIndex, result)
                    }
                }
            }
            results.append(contentsOf: orderedResults.compactMap { $0 })
            await archiveProvider.discardScanMaterialization(at: materializedRoot)
            // Known non-playable resources are a completed archive outcome,
            // not a reason to repeatedly rematerialize the whole container.
            if results.allSatisfy({ result in
                switch result {
                case .success, .unsupported:
                    return true
                case .archiveCompleted, .failure:
                    return false
                }
            }) {
                results.append(.archiveCompleted(await ArchiveScanSignature.enrich(completedCandidate)))
            }
            return results
        } catch {
            return [failure(candidate, stage: .archiveListing, message: error.localizedDescription)]
        }
    }

    private func materialize(_ candidate: ScanCandidate, archiveEntry: String) async throws -> URL {
        let extensionName = candidate.route?.formatExtension
            ?? URL(fileURLWithPath: archiveEntry).pathExtension
        guard let module = PlaybackFormatRegistry.module(forPathExtension: extensionName) else {
            throw ZipArchiveSupport.ArchiveError.invalidEntryPath(archiveEntry)
        }

        switch module.archiveMaterialization {
        case .selectedEntry:
            return try await ScanOperationTimeout.run(kind: .archiveExtraction, description: "extracting \(candidate.identityDescription)") {
                try await archiveProvider.materialize(archiveURL: candidate.sourceURL, entryPath: archiveEntry)
            }
        case .completeSet, .completeSetWithLazyUSFAliases:
            let root = try await ScanOperationTimeout.run(kind: .archiveExtraction, description: "extracting dependency set \(candidate.sourceURL.lastPathComponent)") {
                try await archiveProvider.materializeArchive(at: candidate.sourceURL)
            }
            if case .completeSetWithLazyUSFAliases = module.archiveMaterialization {
                try ZipArchiveSupport.prepareLazyUSFDependencies(in: root)
            }
            if extensionName.lowercased() == "txtp" {
                try ZipArchiveSupport.prepareTXTPDependencies(in: root)
            }
            return ZipArchiveSupport.archiveMemberURL(in: root, entryPath: archiveEntry)
        }
    }

    private func processFile(
        _ candidate: ScanCandidate,
        fileURL: URL? = nil
    ) async throws -> ScanPipelineResult {
        guard let route = candidate.route ?? pluginRegistry.route(
            for: URL(fileURLWithPath: candidate.identity.archiveEntry ?? candidate.sourceURL.path).pathExtension,
            archiveMember: candidate.isArchiveMember
        ) else {
            return .unsupported(candidate)
        }
        guard let handler = handlerRegistry.handler(for: route) else {
            return failure(candidate, stage: .routing, message: "No handler registered for \(route.pluginID)")
        }
        if KDTSequenceDetector.isSilentHillSequenceBank(fileURL ?? candidate.sourceURL) {
            return .unsupported(candidate)
        }
        if WwiseBankDetector.isEventBank(fileURL ?? candidate.sourceURL) {
            return .unsupported(candidate)
        }
        if HeaderlessSS2Detector.isUnsupportedResource(fileURL ?? candidate.sourceURL) {
            return .unsupported(candidate)
        }
        if route.usesDeferredSingleTrackMetadata {
            return .success(candidate, Self.catalogInspection(route: route))
        }
        let inspection = try await inspectionScheduler.withPermit {
            try await ScanOperationTimeout.run(kind: .metadataInspection, description: "inspecting \(candidate.identityDescription)") {
                try await handler.inspect(fileURL: fileURL ?? candidate.sourceURL, route: route)
            }
        }
        return .success(candidate, inspection)
    }

    private static func catalogInspection(route: ScanRoute) -> ScanInspection {
        ScanInspection(
            route: route,
            tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: nil)]
        )
    }

    private func processMaterializedArchiveMember(
        member: ScanArchiveMember,
        candidate: ScanCandidate,
        materializedRoot: URL
    ) async -> ScanPipelineResult {
        do {
            try Task.checkCancellation()
            let materializedURL = ZipArchiveSupport.archiveMemberURL(
                in: materializedRoot,
                entryPath: member.entryPath
            )
            return try await processFile(candidate, fileURL: materializedURL)
        } catch is CancellationError {
            return failure(candidate, stage: .archiveExtraction, message: "Cancelled")
        } catch {
            return failure(candidate, stage: .metadata, message: error.localizedDescription)
        }
    }

    private func failure(
        _ candidate: ScanCandidate,
        stage: ScanFailureStage,
        message: String
    ) -> ScanPipelineResult {
        .failure(ScanFailure(
            identity: candidate.identity,
            fingerprint: candidate.fingerprint,
            route: candidate.route,
            stage: stage,
            message: message
        ))
    }
}

private extension ScanRoute {
    var usesDeferredSingleTrackMetadata: Bool {
        structurePolicy == .knownSingle && metadataPolicy == .optionalDeferred
    }
}

private final class ScanPlanCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let count: Int
    private var nextIndex = 0

    init(count: Int) {
        self.count = count
    }

    func take() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard nextIndex < count else { return nil }
        defer { nextIndex += 1 }
        return nextIndex
    }
}

private final class ScanCompletionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func current() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private extension ScanCandidate {
    var identityDescription: String {
        if let archiveEntry = identity.archiveEntry {
            return "\(identity.path)#\(archiveEntry)"
        }
        return identity.path
    }
}

private extension Array {
    func batched(maximumCount: Int) -> [ArraySlice<Element>] {
        guard !isEmpty else { return [] }
        let size = Swift.max(1, maximumCount)
        return stride(from: startIndex, to: endIndex, by: size).map {
            self[$0..<Swift.min($0 + size, endIndex)]
        }
    }
}
