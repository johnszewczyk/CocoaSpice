import Darwin
import Dispatch
import ArchiveCacheCore
import ArchiveMaterializationCore
import Foundation

enum ZipArchiveSupport {
    static var cacheDirectoryURL: URL { cacheRootURL() }

    static let supportedArchiveExtensions: Set<String> = ["zip", "7z", "lha", "rsn", "tzst", "zst", "zstd"]
    private static let archiveListingTimeout: TimeInterval = 30
    private static let archiveExtractionTimeout: TimeInterval = 600
    private static let archiveListingMaximumBytes = 64 * 1024 * 1024
    /// Archive commands are deliberately one-thread-per-process so a playlist
    /// open cannot make every 7zz process spawn its own full-width worker pool.
    // Leave one cooperative runtime thread free while bounded extractor jobs
    // are running. Eight simultaneous archive jobs on this host deadlock;
    // seven complete concurrently.
    static let archiveProcessConcurrency = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    private static let processRunner = ArchiveProcessRunner(configuration: .init(
        environment: archiveProcessEnvironment(),
        temporaryDirectory: FileManager.default.temporaryDirectory,
        temporaryFilePrefix: "CocoaSpice-process",
        maxConcurrency: archiveProcessConcurrency,
        listingTimeout: archiveListingTimeout,
        extractionTimeout: archiveExtractionTimeout,
        capturedOutputMaximumBytes: Int64(archiveListingMaximumBytes)
    ))
    private static let cacheMaintenanceQueue = DispatchQueue(
        label: "com.cocoaspice.archive-cache-maintenance",
        qos: .utility
    )
    private static let playbackLease = ArchivePlaybackLease()
    private static let cacheStore = ArchiveCacheStore(cacheRootURL: cacheRootURL())
    private static let cacheMaterializer = ArchiveCacheMaterializer(
        cacheStore: cacheStore,
        playbackLease: playbackLease
    )
    private static let playbackMaterializer = ArchivePlaybackMaterializer(
        cacheRootURL: cacheRootURL(),
        preferenceKeys: ArchiveCachePreferenceKeys(
            modeKey: AppDefaultsKey.archiveCacheMode,
            limitKey: AppDefaultsKey.archiveCacheLimitBytes
        )
    )

    struct ArchiveEntry: Hashable, Sendable {
        let archiveURL: URL
        let entryPath: String
    }

    struct PlayableEntryListing: Sendable {
        let entries: [ArchiveEntry]
        let scanSignature: String?
    }

    struct CacheSummary: Sendable {
        let fileCount: Int
        let byteCount: Int64
        let availableBytes: Int64?

        var displaySize: String {
            ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        }
    }

    struct ScratchRecovery: Sendable {
        let rootCount: Int
        let byteCount: Int64
    }

    enum ArchiveError: LocalizedError {
        case unsupportedArchive(URL)
        case processFailed(executable: String, message: String)
        case invalidEntryPath(String)
        case insufficientStorage(requiredBytes: Int64)
        case cacheLimitExceeded(limitBytes: Int64)
        case listingLimitExceeded(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedArchive(let url):
                return "Unsupported archive format: \(url.lastPathComponent)"
            case .processFailed(let executable, let message):
                return "\(executable) failed: \(message)"
            case .invalidEntryPath(let path):
                return "Invalid archive entry path: \(path)"
            case .insufficientStorage(let requiredBytes):
                return "Archive materialization needs at least \(ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)) of free disk space."
            case .cacheLimitExceeded(let limitBytes):
                return "This archive materialization exceeds the \(ByteCountFormatter.string(fromByteCount: limitBytes, countStyle: .file)) cache limit."
            case .listingLimitExceeded(let message):
                return "Archive listing exceeds the safe playlist limit: \(message)"
            }
        }
    }

    static func canHandle(_ url: URL) -> Bool {
        let url = url.standardizedFileURL
        return supportedArchiveExtensions.contains(url.pathExtension.lowercased())
            || (url.pathExtension.lowercased() == "zst"
                && url.deletingPathExtension().pathExtension.lowercased() == "tar")
    }

    static func cacheSummary() -> CacheSummary {
        let rootURL = materializationCacheRootURL()
        let fileManager = FileManager.default
        let availableBytes = cacheStore.availableCapacityNear(rootURL)
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return CacheSummary(fileCount: 0, byteCount: 0, availableBytes: availableBytes)
        }

        var fileCount = 0
        var byteCount: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            fileCount += 1
            byteCount += Int64(values.fileSize ?? 0)
        }
        return CacheSummary(fileCount: fileCount, byteCount: byteCount, availableBytes: availableBytes)
    }

    static func clearCache() throws {
        playbackLease.clear()
        try playbackMaterializer.clearCache()
    }

    static func discardDisposablePlaybackMaterialization() {
        playbackLease.clear()
        cacheLifecycle().discardDisposablePlaybackMaterialization()
        playbackMaterializer.release()
    }

    /// Launch-time recovery removes interrupted disposable playback work and
    /// obsolete cache material left by earlier releases.
    static func reclaimAbandonedMaterializations() -> ScratchRecovery {
        let recovery = cacheLifecycle().reclaimAbandonedMaterialization()
        return ScratchRecovery(rootCount: recovery.rootCount, byteCount: recovery.byteCount)
    }

    static func listPlayableEntries(
        in archiveURL: URL,
        supportedExtensions: Set<String>
    ) throws -> [ArchiveEntry] {
        try listPlayableEntryListing(
            in: archiveURL,
            supportedExtensions: supportedExtensions
        ).entries
    }

    /// Archive playlists are manifests rather than playable tracks. Keep this
    /// narrow listing separate from playable-source discovery so `.m3u`
    /// members never become playlist tracks on their own.
    static func listPlaylistEntries(in archiveURL: URL) throws -> [ArchiveEntry] {
        let archiveURL = archiveURL.standardizedFileURL
        guard canHandle(archiveURL) else {
            throw ArchiveError.unsupportedArchive(archiveURL)
        }

        if let standaloneEntry = standaloneEntry(in: archiveURL),
           URL(fileURLWithPath: standaloneEntry.entryPath).pathExtension.lowercased() == "m3u" {
            return [standaloneEntry]
        }

        return try listEntries(in: archiveURL).entries
            .map(normalizeEntryPath)
            .compactMap { entryPath in
                guard !entryPath.isEmpty,
                      !entryPath.hasSuffix("/"),
                      !entryPath.hasPrefix("__MACOSX/"),
                      URL(fileURLWithPath: entryPath).pathExtension.lowercased() == "m3u" else {
                    return nil
                }
                return ArchiveEntry(archiveURL: archiveURL, entryPath: entryPath)
            }
    }

    static func listPlayableEntryListing(
        in archiveURL: URL,
        supportedExtensions: Set<String>
    ) throws -> PlayableEntryListing {
        let archiveURL = archiveURL.standardizedFileURL
        guard canHandle(archiveURL) else {
            throw ArchiveError.unsupportedArchive(archiveURL)
        }

        if let standaloneEntry = standaloneEntry(in: archiveURL) {
            let ext = URL(fileURLWithPath: standaloneEntry.entryPath).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else {
                return PlayableEntryListing(entries: [], scanSignature: nil)
            }
            return PlayableEntryListing(entries: [standaloneEntry], scanSignature: nil)
        }

        let listing = try listEntries(in: archiveURL)
        let entries: [ArchiveEntry] = listing.entries
            .map(normalizeEntryPath)
            .compactMap { rawEntry in
                let normalized = rawEntry
                guard !normalized.isEmpty,
                      !normalized.hasSuffix("/"),
                      !normalized.hasPrefix("__MACOSX/") else {
                    return nil
                }
                let ext = URL(fileURLWithPath: normalized).pathExtension.lowercased()
                // UADE modules identify their replayer in a filename prefix
                // (`mod.title`, `med.song`, `np2.track`) rather than in the
                // final suffix. Keep the ordinary extension filter for every
                // other format, but admit those prefix-led Amiga members.
                let isAmigaMember = PlaybackFormatRegistry.admitsAmigaPrefix(path: normalized)
                guard supportedExtensions.contains(ext) || isAmigaMember else { return nil }
                return ArchiveEntry(archiveURL: archiveURL, entryPath: normalized)
            }
        return PlayableEntryListing(entries: entries, scanSignature: listing.scanSignature)
    }

    /// Returns tool-reported archive details for an incremental scan. It
    /// never reads member payloads or derives a checksum: ZIP/7z retain the
    /// 7-Zip header report and TAR+Zstandard retains Zstandard's own report.
    /// Unsupported or checksum-less containers return nil and retain ordinary
    /// file-size/modification-date incremental behavior.
    static func scanSignature(for archiveURL: URL) throws -> String? {
        let archiveURL = archiveURL.standardizedFileURL
        switch archiveKind(for: archiveURL) {
        case .zip, .sevenZip, .lha:
            return try listEntries(in: archiveURL).scanSignature
        case .tar:
            return nil
        case .tarZstandard:
            let data = try runProcess(
                executable: try executable(named: "zstd"),
                arguments: ["-lv", archiveURL.path]
            )
            let report = String(decoding: data, as: UTF8.self)
            guard report.contains("Check: XXH64") else { return nil }
            return "zstd-report:\n\(report)"
        case .rsn:
            return nil
        case .singleFileZstandard:
            return nil
        }
    }

    static func materializePlayableFile(for track: TrackItem) throws -> URL {
        switch track.source {
        case .file(let url):
            return url
        case .zipEntry(let archiveURL, let entryPath):
            guard let requirement = PlaybackFormatRegistry.archiveMaterialization(for: [entryPath]) else {
                throw ArchiveError.invalidEntryPath(entryPath)
            }
            return try playbackMaterializer.materialize(
                archiveURL: archiveURL,
                entryPath: entryPath,
                requirement: requirement
            )
        }
    }

    static func materializeEntry(archiveURL: URL, entryPath: String) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        let normalizedEntryPath = normalizeEntryPath(entryPath)

        // A TAR+Zstandard stream must be decompressed from its beginning, but
        // a selected-entry decoder still needs only one member. Extract that
        // member into its durable selection cache; expanding every sibling
        // makes small SPC playback wait on an unrelated archive-sized write.
        if archiveKind(for: archiveURL) == .tarZstandard {
            let rootURL = try materializeEntries(at: archiveURL, entryPaths: [normalizedEntryPath])
            let memberURL = archiveMemberURL(in: rootURL, entryPath: normalizedEntryPath)
            guard FileManager.default.fileExists(atPath: memberURL.path) else {
                throw ArchiveError.invalidEntryPath(entryPath)
            }
            return memberURL
        }

        let policy = ArchiveCachePolicy.load()
        return try withCacheErrors {
            let destinationURL = try cacheMaterializer.materializeEntry(
                archiveURL: archiveURL,
                entryPath: normalizedEntryPath,
                policy: policy
            ) { temporaryURL in
                try runArchiveTool(
                    ArchiveToolRouting.selectedEntryToStdout(
                        kind: archiveKind(for: archiveURL),
                        archiveURL: archiveURL,
                        entryPath: normalizedEntryPath
                    ),
                    outputURL: temporaryURL
                )
            }
            scheduleDurableCacheMaintenance(preserving: archiveCacheURL(for: archiveURL))
            return destinationURL
        }
    }

    /// Reads a small archive-side manifest without creating playback-cache
    /// state. Queue construction needs this for embedded M3U files before the
    /// user has chosen anything to play.
    static func contentsOfEntry(archiveURL: URL, entryPath: String) throws -> Data {
        let archiveURL = archiveURL.standardizedFileURL
        let normalizedEntryPath = normalizeEntryPath(entryPath)
        guard isSafeEntryPath(normalizedEntryPath) else {
            throw ArchiveError.invalidEntryPath(entryPath)
        }

        return try ArchiveManifestReader().read(entryPath: normalizedEntryPath) { rootURL, memberURL in
            if archiveKind(for: archiveURL) == .tarZstandard {
                try extractTarZstandardEntries(
                    from: archiveURL,
                    entryPaths: [normalizedEntryPath],
                    into: rootURL
                )
            } else {
                try runArchiveTool(
                    ArchiveToolRouting.selectedEntryToStdout(
                        kind: archiveKind(for: archiveURL),
                        archiveURL: archiveURL,
                        entryPath: normalizedEntryPath
                    ),
                    outputURL: memberURL
                )
            }
        }
    }

    static func materializeArchive(at archiveURL: URL) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        guard archiveKind(for: archiveURL) != .singleFileZstandard else {
            throw ArchiveError.unsupportedArchive(archiveURL)
        }
        let policy = ArchiveCachePolicy.load()
        return try withCacheErrors {
            try cacheMaterializer.materializeCompleteSet(
                archiveURL: archiveURL,
                policy: policy,
                activePlaybackRoot: playbackLease.path.map(URL.init(fileURLWithPath:))
            ) { stagingURL in
                try runArchiveTool(
                    ArchiveToolRouting.completeSet(
                        kind: archiveKind(for: archiveURL),
                        archiveURL: archiveURL,
                        destinationURL: stagingURL
                    )
                )
            }
        }
    }

    /// Materializes all selected playable members with one extractor process.
    /// Deep scanning needs every selected member, so launching a process per
    /// member only adds startup and temporary-file overhead.
    static func materializeEntries(at archiveURL: URL, entryPaths: [String]) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        guard archiveKind(for: archiveURL) != .singleFileZstandard else {
            throw ArchiveError.unsupportedArchive(archiveURL)
        }
        let policy = ArchiveCachePolicy.load()
        return try withCacheErrors {
            let rootURL = try cacheMaterializer.materializeEntries(
                archiveURL: archiveURL,
                entryPaths: entryPaths,
                policy: policy
            ) { stagingURL, normalizedPaths in
                if archiveKind(for: archiveURL) == .tarZstandard {
                    try extractTarZstandardEntries(
                        from: archiveURL,
                        entryPaths: normalizedPaths,
                        into: stagingURL
                    )
                } else {
                    try runArchiveTool(
                        ArchiveToolRouting.selectedEntries(
                            kind: archiveKind(for: archiveURL),
                            archiveURL: archiveURL,
                            entryPaths: normalizedPaths,
                            destinationURL: stagingURL
                        )
                    )
                }
            }
            // LRU accounting walks the whole durable cache, so it must not
            // delay decoder startup for a cold archive member.
            scheduleDurableCacheMaintenance(preserving: archiveCacheURL(for: archiveURL))
            return rootURL
        }
    }

    static func archiveMemberURL(in materializedArchiveURL: URL, entryPath: String) -> URL {
        ArchiveEntryPath.components(entryPath).reduce(materializedArchiveURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
    }

    static func archiveCacheURL(for archiveURL: URL) -> URL {
        cacheStore.archiveCacheURL(for: archiveURL, policy: ArchiveCachePolicy.load())
    }

    private static func cacheRootURL() -> URL {
        let fileManager = FileManager.default
        let cachesURL =
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return cachesURL
            .appendingPathComponent("CocoaSpice", isDirectory: true)
            .appendingPathComponent("ArchiveCache", isDirectory: true)
    }

    private static func cacheLifecycle() -> ArchiveCacheLifecycle {
        cacheStore.lifecycle
    }

    private static func materializationCacheRootURL() -> URL {
        cacheStore.materializationRootURL(policy: ArchiveCachePolicy.load())
    }

    private static func enforceDurableCacheLimit(preserving protectedRoot: URL) throws {
        try withCacheErrors {
            try cacheStore.enforceLimit(
                policy: ArchiveCachePolicy.load(),
                preserving: protectedRoot,
                activePlaybackRoot: playbackLease.path.map(URL.init(fileURLWithPath:))
            )
        }
    }

    private static func withCacheErrors<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as ArchiveCacheStore.Error {
            switch error {
            case .insufficientStorage(let requiredBytes):
                throw ArchiveError.insufficientStorage(requiredBytes: requiredBytes)
            case .cacheLimitExceeded(let limitBytes):
                throw ArchiveError.cacheLimitExceeded(limitBytes: limitBytes)
            }
        }
    }

    private static func scheduleDurableCacheMaintenance(preserving protectedRoot: URL) {
        guard ArchiveCachePolicy.load().isEnabled else { return }
        cacheMaintenanceQueue.async {
            try? enforceDurableCacheLimit(preserving: protectedRoot)
        }
    }

    private static func listEntries(in archiveURL: URL) throws -> ArchiveListing {
        switch archiveKind(for: archiveURL) {
        case .zip, .sevenZip, .lha:
            let data = try runProcess(
                executable: try executable(named: "7zz"),
                arguments: ["l", "-mmt=1", "-slt", "-ba", archiveURL.path]
            )
            return try parseListingErrors {
                try ArchiveListingParser.parseSevenZipReport(data)
            }
        case .rsn:
            let data = try runProcess(
                executable: try executable(named: "lsar"),
                arguments: ["-j", archiveURL.path]
            )
            return try parseListingErrors {
                do {
                    return try ArchiveListingParser.parseRSNListing(data)
                } catch ArchiveListingParserError.invalidListing {
                    throw ArchiveError.processFailed(executable: "lsar", message: "invalid JSON listing")
                }
            }
        case .tar:
            let data = try runProcess(
                executable: try executable(named: "tar"),
                arguments: ["-tf", archiveURL.path]
            )
            return try parseListingErrors {
                try ArchiveListingParser.parseTarListing(data)
            }
        case .tarZstandard:
            let data = try runTarZstandardListing(archiveURL)
            return try parseListingErrors {
                try ArchiveListingParser.parseTarListing(data)
            }
        case .singleFileZstandard:
            throw ArchiveError.unsupportedArchive(archiveURL)
        }
    }

    private static func parseListingErrors(
        _ parse: () throws -> ArchiveListing
    ) throws -> ArchiveListing {
        do {
            return try parse()
        } catch ArchiveListingParserError.outputLimitExceeded {
            throw ArchiveError.listingLimitExceeded("more than 64 MiB of tool output")
        } catch ArchiveListingParserError.entryCountLimitExceeded {
            throw ArchiveError.listingLimitExceeded("more than 250000 entries")
        } catch ArchiveListingParserError.entryNameLimitExceeded(let name) {
            throw ArchiveError.listingLimitExceeded(
                "entry name longer than 32768 bytes: \(name)"
            )
        }
    }

    private static func archiveKind(for archiveURL: URL) -> ArchiveContainerKind {
        ArchiveContainerKind(archiveURL: archiveURL) ?? .rsn
    }

    private static func standaloneEntry(in archiveURL: URL) -> ArchiveEntry? {
        guard archiveKind(for: archiveURL) == .singleFileZstandard else { return nil }
        let entryPath = archiveURL.deletingPathExtension().lastPathComponent
        guard !entryPath.isEmpty, ArchiveEntryPath.isSafe(entryPath) else { return nil }
        return ArchiveEntry(archiveURL: archiveURL, entryPath: entryPath)
    }

    private static func executable(named name: String) throws -> String {
        let environmentKey: String
        switch name {
        case "7zz": environmentKey = "COCOASPICE_7Z_BINARY"
        case "unar": environmentKey = "COCOASPICE_UNAR_BINARY"
        case "lsar": environmentKey = "COCOASPICE_LSAR_BINARY"
        case "tar": environmentKey = "COCOASPICE_TAR_BINARY"
        case "zstd": environmentKey = "COCOASPICE_ZSTD_BINARY"
        default: environmentKey = "COCOASPICE_ZIPINFO_BINARY"
        }

        let candidates = [
            ProcessInfo.processInfo.environment[environmentKey],
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ].compactMap { $0 }

        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw ArchiveError.processFailed(
            executable: name,
            message: "Install the required archive tool, then retry archive playback."
        )
    }

    private static func archiveProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let inheritedPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            + inheritedPaths.filter { !["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].contains($0) }
        environment["PATH"] = paths.joined(separator: ":")
        return environment
    }

    private static func materializeTarZstandardArchive(_ archiveURL: URL, into destinationURL: URL) throws {
        try runZstandardTarPipeline(
            archiveURL: archiveURL,
            tarArguments: ["-xf", "-", "-C", destinationURL.path]
        )
    }

    /// BSD tar's built-in Zstandard helper is unreliable for selected-member
    /// extraction. Stream zstd into tar ourselves so a cold selection never
    /// writes and rereads a complete temporary TAR just to obtain one member.
    private static func extractTarZstandardEntries(
        from archiveURL: URL,
        entryPaths: [String],
        into destinationURL: URL
    ) throws {
        let literalPaths = entryPaths.filter { !containsTarOctalEscape($0) }
        if !literalPaths.isEmpty {
            try runZstandardTarPipeline(
                archiveURL: archiveURL,
                tarArguments: ["-xf", "-", "-C", destinationURL.path]
                    + tarMemberSelectionPatterns(literalPaths),
                allowEarlyConsumerExit: true
            )
        }

        // BSD tar renders non-UTF-8 pathname bytes in listings as `\\255`.
        // Passing that display text back as an argv string asks for four
        // printable characters, not the original byte. Its NUL-delimited
        // files-from input preserves the recovered raw pathname exactly.
        for entryPath in entryPaths where containsTarOctalEscape(entryPath) {
            let selectionURL = destinationURL.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).members", isDirectory: false)
            defer { try? FileManager.default.removeItem(at: selectionURL) }
            var selectionData = tarMemberPathData(fromListingPath: entryPath)
            selectionData.append(0)
            try selectionData.write(to: selectionURL, options: .atomic)

            let outputURL = archiveMemberURL(in: destinationURL, entryPath: entryPath)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try runZstandardTarPipelineWritingOutput(
                archiveURL: archiveURL,
                tarArguments: ["-xOf", "-", "--null", "-T", selectionURL.path],
                outputURL: outputURL,
                allowEarlyConsumerExit: true
            )
        }
    }

    private static func containsTarOctalEscape(_ path: String) -> Bool {
        let bytes = Array(path.utf8)
        guard bytes.count >= 4 else { return false }
        for index in 0...(bytes.count - 4) where bytes[index] == 0x5C {
            if bytes[(index + 1)...(index + 3)].allSatisfy({ (0x30...0x37).contains($0) }) {
                return true
            }
        }
        return false
    }

    private static func tarMemberPathData(fromListingPath path: String) -> Data {
        let bytes = Array(path.utf8)
        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x5C,
               index + 3 < bytes.count,
               bytes[(index + 1)...(index + 3)].allSatisfy({ (0x30...0x37).contains($0) }) {
                let value = bytes[(index + 1)...(index + 3)].reduce(0) { partial, digit in
                    partial * 8 + Int(digit - 0x30)
                }
                decoded.append(UInt8(value))
                index += 4
            } else {
                decoded.append(bytes[index])
                index += 1
            }
        }
        return Data(decoded)
    }

    /// BSD tar treats selected member arguments as patterns. Quote its pattern
    /// metacharacters so a scanned archive path is always an exact member name.
    private static func tarMemberSelectionPatterns(_ entryPaths: [String]) -> [String] {
        ArchiveEntryPath.tarMemberSelectionPatterns(entryPaths)
    }

    /// BSD tar's automatic Zstandard helper exits spuriously when many archive
    /// listings run at once. Use the reliable `zstd` binary explicitly.
    private static func runTarZstandardListing(_ archiveURL: URL) throws -> Data {
        try acquireProcessPermit()
        defer { processRunner.releasePermit() }

        let outputURL = try processOutputURL()
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let archiveData = Pipe()
        let decompressor = Process()
        decompressor.executableURL = URL(fileURLWithPath: try executable(named: "zstd"))
        decompressor.arguments = ["-d", "-q", "-c", archiveURL.path]
        decompressor.environment = archiveProcessEnvironment()
        decompressor.standardOutput = archiveData
        let decompressorError = Pipe()
        decompressor.standardError = decompressorError

        let lister = Process()
        lister.executableURL = URL(fileURLWithPath: try executable(named: "tar"))
        lister.arguments = ["-tf", "-"]
        lister.environment = archiveProcessEnvironment()
        lister.standardInput = archiveData
        lister.standardOutput = outputHandle
        let listerError = Pipe()
        lister.standardError = listerError

        let decompressorCompletion = DispatchSemaphore(value: 0)
        let listerCompletion = DispatchSemaphore(value: 0)
        decompressor.terminationHandler = { _ in decompressorCompletion.signal() }
        lister.terminationHandler = { _ in listerCompletion.signal() }
        defer {
            decompressor.terminationHandler = nil
            lister.terminationHandler = nil
        }

        try lister.run()
        do {
            try decompressor.run()
        } catch {
            lister.terminate()
            lister.waitUntilExit()
            throw error
        }
        try? archiveData.fileHandleForWriting.close()
        try? archiveData.fileHandleForReading.close()
        try? decompressorError.fileHandleForWriting.close()
        try? listerError.fileHandleForWriting.close()

        let decompressorErrors = ArchiveProcessOutputCollector()
        let listerErrors = ArchiveProcessOutputCollector()
        let readers = DispatchGroup()
        for (handle, collector) in [
            (decompressorError.fileHandleForReading, decompressorErrors),
            (listerError.fileHandleForReading, listerErrors)
        ] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                collector.set(handle.readDataToEndOfFile())
                try? handle.close()
                readers.leave()
            }
        }

        do {
            try waitForProcess(lister, completion: listerCompletion, executable: lister.executableURL!.path, timeout: archiveListingTimeout)
            try waitForProcess(decompressor, completion: decompressorCompletion, executable: decompressor.executableURL!.path, timeout: archiveListingTimeout)
        } catch {
            if decompressor.isRunning { decompressor.terminate() }
            if lister.isRunning { lister.terminate() }
            if decompressor.isRunning { decompressor.waitUntilExit() }
            if lister.isRunning { lister.waitUntilExit() }
            readers.wait()
            throw error
        }
        readers.wait()
        try outputHandle.close()

        // `tar -tf -` can close the pipe after it has parsed the TAR end
        // markers. Depending on the zstd build, that arrives as SIGPIPE or
        // its normal exit-70 "Write error ... Broken pipe" report. Tar is
        // the authoritative consumer here: accept only that precise upstream
        // closure after tar has completed successfully.
        let decompressorErrorText = String(
            decoding: decompressorErrors.value,
            as: UTF8.self
        )
        let decompressorReportedBrokenPipe = isExpectedZstandardPipeClosure(
            exitStatus: decompressor.terminationStatus,
            terminationReason: decompressor.terminationReason,
            stderr: decompressorErrorText
        )
        let decompressorSucceeded = decompressor.terminationStatus == 0
            || decompressorReportedBrokenPipe
        guard decompressorSucceeded, lister.terminationStatus == 0 else {
            let messages = [decompressorErrors.value, listerErrors.value]
                .map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            throw ArchiveError.processFailed(
                executable: "zstd/tar",
                message: messages.isEmpty ? "exit code \(decompressor.terminationStatus)/\(lister.terminationStatus)" : messages.joined(separator: "\n")
            )
        }
        let outputBytes = Int64((try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard outputBytes <= Int64(archiveListingMaximumBytes) else {
            throw ArchiveError.listingLimitExceeded("more than 64 MiB of tool output")
        }
        return try Data(contentsOf: outputURL, options: .mappedIfSafe)
    }

    static func isExpectedZstandardPipeClosure(
        exitStatus: Int32,
        terminationReason: Process.TerminationReason,
        stderr: String
    ) -> Bool {
        (terminationReason == .uncaughtSignal && exitStatus == SIGPIPE)
            || (terminationReason == .exit
                && exitStatus == 70
                && stderr.localizedCaseInsensitiveContains("write error")
                && stderr.localizedCaseInsensitiveContains("broken pipe"))
    }

    private static func archiveFilePaths(in rootURL: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ArchiveError.processFailed(executable: "tar", message: "Could not enumerate extracted archive.")
        }
        let rootPath = rootURL.standardizedFileURL.path + "/"
        return enumerator.compactMap { element in
            guard let url = element as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  url.standardizedFileURL.path.hasPrefix(rootPath) else {
                return nil
            }
            return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
        }.sorted()
    }

    private static func isSafeEntryPath(_ entryPath: String) -> Bool {
        ArchiveEntryPath.isSafe(entryPath)
    }

    private static func normalizeEntryPath(_ entryPath: String) -> String {
        ArchiveEntryPath.normalized(entryPath)
    }

    private static func runProcess(
        executable: String,
        arguments: [String]
    ) throws -> Data {
        // Listing is bounded tightly, but a valid extraction must be allowed
        // to decompress a large solid TAR+Zstandard source. The scan pipeline
        // uses the same 10-minute extraction boundary.
        let executableName = URL(fileURLWithPath: executable).lastPathComponent
        let isExtraction = executableName == "unar"
            || arguments.first == "x"
            || arguments.contains("-xf")
        do {
            return try processRunner.run(
                executable: executable,
                arguments: arguments,
                operation: isExtraction ? .extraction : .listing
            )
        } catch {
            throw mapProcessRunnerError(error)
        }
    }

    private static func runArchiveTool(
        _ invocation: ArchiveToolInvocation,
        outputURL: URL? = nil
    ) throws {
        switch invocation {
        case let .process(executableName, arguments):
            let executable = try executable(named: executableName)
            if let outputURL {
                try runProcessWritingOutput(
                    executable: executable,
                    arguments: arguments,
                    outputURL: outputURL
                )
            } else {
                _ = try runProcess(executable: executable, arguments: arguments)
            }
        case let .zstandardTar(
            zstdExecutableName,
            zstdArguments,
            tarExecutableName,
            tarArguments,
            allowEarlyConsumerExit
        ):
            try runZstandardTarPipeline(
                zstdExecutable: try executable(named: zstdExecutableName),
                zstdArguments: zstdArguments,
                tarExecutable: try executable(named: tarExecutableName),
                tarArguments: tarArguments,
                outputURL: outputURL,
                allowEarlyConsumerExit: allowEarlyConsumerExit
            )
        }
    }

    private static func runZstandardTarPipeline(
        archiveURL: URL,
        tarArguments: [String],
        allowEarlyConsumerExit: Bool = false
    ) throws {
        try runZstandardTarPipeline(
            zstdExecutable: try executable(named: "zstd"),
            zstdArguments: ["-d", "-q", "-c", archiveURL.path],
            tarExecutable: try executable(named: "tar"),
            tarArguments: tarArguments,
            outputURL: nil,
            allowEarlyConsumerExit: allowEarlyConsumerExit
        )
    }

    private static func runZstandardTarPipelineWritingOutput(
        archiveURL: URL,
        tarArguments: [String],
        outputURL: URL,
        allowEarlyConsumerExit: Bool = false
    ) throws {
        try runZstandardTarPipeline(
            zstdExecutable: try executable(named: "zstd"),
            zstdArguments: ["-d", "-q", "-c", archiveURL.path],
            tarExecutable: try executable(named: "tar"),
            tarArguments: tarArguments,
            outputURL: outputURL,
            allowEarlyConsumerExit: allowEarlyConsumerExit
        )
    }

    /// Runs `zstd -d -c` directly into BSD tar. TAR+Zstandard is necessarily
    /// sequential, but it does not need a second full disk pass through a
    /// temporary TAR before playback can begin.
    private static func runZstandardTarPipeline(
        zstdExecutable: String,
        zstdArguments: [String],
        tarExecutable: String,
        tarArguments: [String],
        outputURL: URL?,
        allowEarlyConsumerExit: Bool = false
    ) throws {
        try acquireProcessPermit()
        defer { processRunner.releasePermit() }

        let transport = Pipe()
        let zstd = Process()
        zstd.executableURL = URL(fileURLWithPath: zstdExecutable)
        zstd.arguments = zstdArguments
        zstd.environment = archiveProcessEnvironment()
        zstd.standardOutput = transport

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: tarExecutable)
        tar.arguments = tarArguments
        tar.environment = archiveProcessEnvironment()
        tar.standardInput = transport

        var outputHandle: FileHandle?
        if let outputURL {
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: outputURL)
            tar.standardOutput = handle
            outputHandle = handle
        }
        defer { try? outputHandle?.close() }

        let zstdError = Pipe()
        let tarError = Pipe()
        zstd.standardError = zstdError
        tar.standardError = tarError

        let zstdCompletion = DispatchSemaphore(value: 0)
        let tarCompletion = DispatchSemaphore(value: 0)
        zstd.terminationHandler = { _ in zstdCompletion.signal() }
        tar.terminationHandler = { _ in tarCompletion.signal() }
        defer {
            zstd.terminationHandler = nil
            tar.terminationHandler = nil
        }

        let zstdErrorHandle = zstdError.fileHandleForReading
        let tarErrorHandle = tarError.fileHandleForReading
        let zstdCollector = ArchiveProcessOutputCollector()
        let tarCollector = ArchiveProcessOutputCollector()
        let readers = DispatchGroup()
        for (handle, collector) in [(zstdErrorHandle, zstdCollector), (tarErrorHandle, tarCollector)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                collector.set(handle.readDataToEndOfFile())
                try? handle.close()
                readers.leave()
            }
        }

        do {
            // Start tar first: it is ready to consume as soon as zstd emits
            // the first block, so the pipe never becomes a startup bottleneck.
            try tar.run()
            try zstd.run()
            try transport.fileHandleForWriting.close()
            try zstdError.fileHandleForWriting.close()
            try tarError.fileHandleForWriting.close()
            try waitForProcess(
                zstd,
                completion: zstdCompletion,
                executable: zstdExecutable,
                timeout: archiveExtractionTimeout
            )
            try waitForProcess(
                tar,
                completion: tarCompletion,
                executable: tarExecutable,
                timeout: archiveExtractionTimeout
            )
        } catch {
            if zstd.isRunning { zstd.terminate() }
            if tar.isRunning { tar.terminate() }
            readers.wait()
            throw error
        }
        readers.wait()

        let tarSucceeded = tar.terminationStatus == 0
        guard tarSucceeded else {
            throw ArchiveError.processFailed(
                executable: "tar",
                message: processErrorText(tarCollector.value, status: tar.terminationStatus)
            )
        }
        let zstdSucceeded = zstd.terminationStatus == 0
            || (allowEarlyConsumerExit && isExpectedZstandardPipeClosure(
                exitStatus: zstd.terminationStatus,
                terminationReason: zstd.terminationReason,
                stderr: String(decoding: zstdCollector.value, as: UTF8.self)
            ))
        guard zstdSucceeded else {
            throw ArchiveError.processFailed(
                executable: "zstd",
                message: processErrorText(zstdCollector.value, status: zstd.terminationStatus)
            )
        }
    }

    private static func processErrorText(_ data: Data, status: Int32) -> String {
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "exit code \(status)" : text
    }

    private static func runProcessWritingOutput(
        executable: String,
        arguments: [String],
        outputURL: URL
    ) throws {
        do {
            try processRunner.runWritingOutput(
                executable: executable,
                arguments: arguments,
                outputURL: outputURL,
                operation: .extraction
            )
        } catch {
            throw mapProcessRunnerError(error)
        }
    }

    private static func processOutputURL() throws -> URL {
        // Process stdout is an immediately removed scratch file, not archive
        // material. Keep it in the system temporary directory so listing a
        // source neither creates nor requires the playback cache.
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "CocoaSpice-process-\(UUID().uuidString)",
            isDirectory: false
        )
    }

    private static func acquireProcessPermit() throws {
        do {
            try processRunner.acquirePermit()
        } catch {
            throw mapProcessRunnerError(error)
        }
    }

    private static func mapProcessRunnerError(_ error: Error) -> Error {
        switch error {
        case is CancellationError:
            return CancellationError()
        case let error as ArchiveProcessRunnerError:
            switch error {
            case let .timedOut(executable, seconds):
                return ArchiveError.processFailed(
                    executable: executable,
                    message: "timed out after \(seconds) seconds"
                )
            case let .failed(executable, _, message):
                return ArchiveError.processFailed(executable: executable, message: message)
            case .outputLimitExceeded:
                return ArchiveError.listingLimitExceeded("more than 64 MiB of tool output")
            }
        default:
            return error
        }
    }

    /// Process completion wakes immediately through the termination handler.
    /// The bounded wait exists only to observe task cancellation and timeout;
    /// it no longer imposes a polling delay on successful tiny archive jobs.
    private static func waitForProcess(
        _ process: Process,
        completion: DispatchSemaphore,
        executable: String,
        timeout: TimeInterval
    ) throws {
        do {
            try processRunner.waitForProcess(
                process,
                completion: completion,
                executable: executable,
                timeout: timeout
            )
        } catch {
            throw mapProcessRunnerError(error)
        }
    }
}
