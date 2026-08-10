import CryptoKit
import Darwin
import Dispatch
import Foundation

enum ZipArchiveSupport {
    static let supportedArchiveExtensions: Set<String> = ["zip", "7z", "rsn", "tzst"]
    private static let archiveListingTimeout: TimeInterval = 30
    private static let archiveExtractionTimeout: TimeInterval = 600
    /// Archive commands are deliberately one-thread-per-process. The scanner
    /// fans those processes across the machine instead of allowing every 7zz
    /// process to spawn its own full-width worker pool.
    // Leave one cooperative runtime thread free while bounded extractor jobs
    // are running. Eight simultaneous archive jobs on this host deadlock;
    // seven complete concurrently.
    static let archiveProcessConcurrency = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    private static let processGate = DispatchSemaphore(value: archiveProcessConcurrency)
    private static let playbackLease = PlaybackLease()

    private enum ArchiveKind {
        case zip
        case sevenZip
        case rsn
        case tarZstandard
    }

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
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return CacheSummary(fileCount: 0, byteCount: 0)
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
        return CacheSummary(fileCount: fileCount, byteCount: byteCount)
    }

    static func clearCache() throws {
        let fileManager = FileManager.default
        for rootURL in [durableCacheRootURL(), disposableCacheRootURL()] where fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
    }

    static func discardDisposablePlaybackMaterialization() {
        playbackLease.clear()
        try? FileManager.default.removeItem(at: disposableCacheRootURL())
    }

    /// Launch-time recovery only. Every scan owns and normally discards its
    /// own root; this removes roots left behind when the previous process was
    /// interrupted before its cleanup scope ran.
    static func reclaimAbandonedScanMaterializations() -> ScratchRecovery {
        let fileManager = FileManager.default
        var count = 0
        var bytes: Int64 = 0

        func discard(_ root: URL) {
            guard fileManager.fileExists(atPath: root.path) else { return }
            bytes += directoryByteCount(root)
            if (try? fileManager.removeItem(at: root)) != nil { count += 1 }
        }

        // Interrupted scan and cache-off playback roots are always disposable.
        discard(scanScratchRootURL())
        discard(disposableCacheRootURL())

        // The pre-policy cache placed archive-key directories directly under
        // ArchiveCache. They are no longer reachable by current materializers
        // and must not strand storage after an app update.
        let root = cacheRootURL()
        let retainedNames: Set<String> = ["DurablePlayback", "ScanScratch", "DisposablePlayback"]
        if let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for child in children where !retainedNames.contains(child.lastPathComponent) {
                discard(child)
            }
        }

        // A durable cache may retain only completed materializations. Staging
        // names are hidden by construction and therefore safe to remove before
        // new playback starts.
        if let children = try? fileManager.contentsOfDirectory(at: durableCacheRootURL(), includingPropertiesForKeys: nil) {
            for child in children where child.lastPathComponent.hasPrefix(".") {
                discard(child)
            }
        }
        return ScratchRecovery(rootCount: count, byteCount: bytes)
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
    /// narrow listing separate from scanner discovery so `.m3u` members never
    /// become database audio rows on their own.
    static func listPlaylistEntries(in archiveURL: URL) throws -> [ArchiveEntry] {
        let archiveURL = archiveURL.standardizedFileURL
        guard canHandle(archiveURL) else {
            throw ArchiveError.unsupportedArchive(archiveURL)
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
                guard supportedExtensions.contains(ext) else { return nil }
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
        case .zip, .sevenZip:
            return try listEntries(in: archiveURL).scanSignature
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
        }
    }

    static func materializePlayableFile(for track: TrackItem) throws -> URL {
        switch track.source {
        case .file(let url):
            return url
        case .zipEntry(let archiveURL, let entryPath):
            let extensionName = URL(fileURLWithPath: entryPath).pathExtension.lowercased()
            guard let module = PlaybackFormatRegistry.module(forPathExtension: extensionName) else {
                throw ArchiveError.invalidEntryPath(entryPath)
            }
            switch module.archiveMaterialization {
            case .selectedEntry:
                let fileURL = try materializeEntry(archiveURL: archiveURL, entryPath: entryPath)
                activatePlaybackLease(for: archiveURL)
                return fileURL
            case .completeSet, .completeSetWithLazyUSFAliases:
                let setURL = try materializeArchive(at: archiveURL)
                if case .completeSetWithLazyUSFAliases = module.archiveMaterialization {
                    try prepareLazyUSFDependencies(in: setURL)
                }
                if extensionName == "txtp" {
                    try prepareTXTPDependencies(in: setURL)
                }
                activatePlaybackLease(for: archiveURL)
                return archiveMemberURL(in: setURL, entryPath: entryPath)
            }
        }
    }

    static func materializeEntry(archiveURL: URL, entryPath: String) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        let normalizedEntryPath = normalizeEntryPath(entryPath)

        // BSD tar can report its Zstandard helper as failed after `-xO` has
        // already written a valid selected member. Read TAR+Zstandard archives
        // to completion into the managed cache instead, then resolve the
        // requested member from that complete set.
        if archiveKind(for: archiveURL) == .tarZstandard {
            if containsTarOctalEscape(normalizedEntryPath) {
                let rootURL = try materializeEntries(at: archiveURL, entryPaths: [normalizedEntryPath])
                let memberURL = archiveMemberURL(in: rootURL, entryPath: normalizedEntryPath)
                guard FileManager.default.fileExists(atPath: memberURL.path) else {
                    throw ArchiveError.invalidEntryPath(entryPath)
                }
                return memberURL
            }
            let rootURL = try materializeArchive(at: archiveURL)
            let memberURL = archiveMemberURL(in: rootURL, entryPath: normalizedEntryPath)
            guard FileManager.default.fileExists(atPath: memberURL.path) else {
                throw ArchiveError.invalidEntryPath(entryPath)
            }
            return memberURL
        }

        let destinationURL = try materializedEntryURL(
            archiveURL: archiveURL,
            entryPath: normalizedEntryPath
        )

        let fileManager = FileManager.default
        let archiveModifiedAt =
            (try? archiveURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        if fileManager.fileExists(atPath: destinationURL.path),
           let extractedModifiedAt = try? destinationURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           extractedModifiedAt >= archiveModifiedAt {
            touchCacheEntry(for: archiveURL)
            return destinationURL
        }

        try prepareDurableCacheWrite(for: archiveURL)

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).partial", isDirectory: false)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        switch archiveKind(for: archiveURL) {
        case .rsn:
            try runProcessWritingOutput(
                executable: try executable(named: "unar"),
                arguments: ["-q", "-f", "-o", "-", archiveURL.path, normalizedEntryPath],
                outputURL: temporaryURL
            )
        case .zip, .sevenZip:
            try runProcessWritingOutput(
                executable: try executable(named: "7zz"),
                arguments: ["x", "-mmt=1", "-so", archiveURL.path, normalizedEntryPath],
                outputURL: temporaryURL
            )
        case .tarZstandard:
            fatalError("TAR+Zstandard entries are materialized as complete archives above")
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        try enforceDurableCacheLimit(preserving: archiveCacheURL(for: archiveURL))
        return destinationURL
    }

    static func materializeArchive(at archiveURL: URL) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        let rootURL = archiveCacheURL(for: archiveURL)
            .appendingPathComponent("set", isDirectory: true)
        let completionURL = rootURL.appendingPathComponent(".complete", isDirectory: false)
        if FileManager.default.fileExists(atPath: completionURL.path) {
            touchCacheEntry(for: archiveURL)
            return rootURL
        }

        try prepareDurableCacheWrite(for: archiveURL)

        let stagingURL = rootURL.deletingLastPathComponent().appendingPathComponent(".set-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stagingURL) }
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        switch archiveKind(for: archiveURL) {
        case .rsn:
            _ = try runProcess(executable: try executable(named: "unar"), arguments: ["-q", "-f", "-D", "-o", stagingURL.path, archiveURL.path])
        case .zip, .sevenZip:
            _ = try runProcess(executable: try executable(named: "7zz"), arguments: ["x", "-mmt=1", "-y", "-o\(stagingURL.path)", archiveURL.path])
        case .tarZstandard:
            try materializeTarZstandardArchive(archiveURL, into: stagingURL)
        }
        try Data().write(to: stagingURL.appendingPathComponent(".complete"))
        try FileManager.default.createDirectory(at: rootURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.moveItem(at: stagingURL, to: rootURL)
        }
        try enforceDurableCacheLimit(preserving: archiveCacheURL(for: archiveURL))
        return rootURL
    }

    /// Materializes all selected playable members with one extractor process.
    /// Deep scanning needs every selected member, so launching a process per
    /// member only adds startup and temporary-file overhead.
    static func materializeEntries(at archiveURL: URL, entryPaths: [String]) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        let normalizedPaths = try Array(Set(entryPaths.map { entryPath in
            let normalized = normalizeEntryPath(entryPath)
            guard !normalized.isEmpty,
                  isSafeEntryPath(normalized) else {
                throw ArchiveError.invalidEntryPath(entryPath)
            }
            return normalized
        })).sorted()
        guard !normalizedPaths.isEmpty else {
            throw ArchiveError.invalidEntryPath("")
        }

        let selectionKey = sha256Hex(normalizedPaths.joined(separator: "\n"))
        let rootURL = archiveCacheURL(for: archiveURL)
            .appendingPathComponent("selection-\(selectionKey)", isDirectory: true)
        let completionURL = rootURL.appendingPathComponent(".complete", isDirectory: false)
        if FileManager.default.fileExists(atPath: completionURL.path) {
            touchCacheEntry(for: archiveURL)
            return rootURL
        }

        try prepareDurableCacheWrite(for: archiveURL)

        let stagingURL = rootURL.deletingLastPathComponent()
            .appendingPathComponent(".selection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stagingURL) }
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        switch archiveKind(for: archiveURL) {
        case .rsn:
            _ = try runProcess(
                executable: try executable(named: "unar"),
                arguments: ["-q", "-f", "-D", "-o", stagingURL.path, archiveURL.path] + normalizedPaths
            )
        case .zip, .sevenZip:
            _ = try runProcess(
                executable: try executable(named: "7zz"),
                arguments: ["x", "-mmt=1", "-y", "-o\(stagingURL.path)", archiveURL.path] + normalizedPaths
            )
        case .tarZstandard:
            try extractTarZstandardEntries(
                from: archiveURL,
                entryPaths: normalizedPaths,
                into: stagingURL
            )
        }

        try Data().write(to: stagingURL.appendingPathComponent(".complete"))
        try FileManager.default.createDirectory(
            at: rootURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.moveItem(at: stagingURL, to: rootURL)
        }
        try enforceDurableCacheLimit(preserving: archiveCacheURL(for: archiveURL))
        return rootURL
    }

    /// Scan extraction is deliberately non-persistent. The scanner consumes a
    /// materialized archive once, then removes it before advancing to another
    /// source. Playback continues to use the durable archive cache above.
    static func materializeEntriesForScan(at archiveURL: URL, entryPaths: [String]) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        let normalizedPaths = try normalizedEntryPaths(entryPaths)
        let rootURL = try makeScanScratchDirectory()
        do {
            try extractEntries(
                from: archiveURL,
                entryPaths: normalizedPaths,
                into: rootURL
            )
            return rootURL
        } catch {
            discardScanMaterialization(at: rootURL)
            throw error
        }
    }

    static func materializeArchiveForScan(at archiveURL: URL) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        let rootURL = try makeScanScratchDirectory()
        do {
            switch archiveKind(for: archiveURL) {
            case .rsn:
                _ = try runProcess(executable: try executable(named: "unar"), arguments: ["-q", "-f", "-D", "-o", rootURL.path, archiveURL.path])
            case .zip, .sevenZip:
                _ = try runProcess(executable: try executable(named: "7zz"), arguments: ["x", "-mmt=1", "-y", "-o\(rootURL.path)", archiveURL.path])
            case .tarZstandard:
                try materializeTarZstandardArchive(archiveURL, into: rootURL)
            }
            return rootURL
        } catch {
            discardScanMaterialization(at: rootURL)
            throw error
        }
    }

    static func discardScanMaterialization(at rootURL: URL) {
        guard rootURL.standardizedFileURL.path.hasPrefix(scanScratchRootURL().path + "/") else { return }
        try? FileManager.default.removeItem(at: rootURL)
    }

    static func materializeInspectionSet(
        archiveURL: URL,
        entryPaths: [String]
    ) throws -> URL {
        guard let policy = PlaybackFormatRegistry.archiveMaterializationForInspection(
            entryPaths: entryPaths
        ) else {
            throw ArchiveError.invalidEntryPath(entryPaths.first ?? "")
        }

        switch policy {
        case .selectedEntry:
            return try materializeEntries(at: archiveURL, entryPaths: entryPaths)
        case .completeSet, .completeSetWithLazyUSFAliases:
            let root = try materializeArchive(at: archiveURL)
            if policy == .completeSetWithLazyUSFAliases {
                try prepareLazyUSFDependencies(in: root)
            }
            if entryPaths.contains(where: {
                URL(fileURLWithPath: $0).pathExtension.lowercased() == "txtp"
            }) {
                try prepareTXTPDependencies(in: root)
            }
            return root
        }
    }

    static func archiveMemberURL(in materializedArchiveURL: URL, entryPath: String) -> URL {
        sanitizedEntryPathComponents(entryPath).reduce(materializedArchiveURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
    }

    static func prepareLazyUSFDependencies(in materializedArchiveURL: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: materializedArchiveURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for libraryURL in contents where libraryURL.pathExtension.lowercased() == "usflib" {
            let aliasURL = libraryURL.deletingPathExtension()
            guard !FileManager.default.fileExists(atPath: aliasURL.path) else { continue }
            try FileManager.default.linkItem(at: libraryURL, to: aliasURL)
        }
    }

    /// Some JoshW Wwise sets are flat archives but their generated TXTP
    /// manifests retain the original directory hierarchy. Build cache-only
    /// hard-link aliases for uniquely named referenced siblings so vgmstream
    /// sees the paths declared by the manifest without modifying the source.
    static func prepareTXTPDependencies(in materializedArchiveURL: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: materializedArchiveURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var filesByLeafName: [String: [URL]] = [:]
        var txtpFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            if fileURL.pathExtension.lowercased() == "txtp" {
                txtpFiles.append(fileURL)
            } else {
                filesByLeafName[fileURL.lastPathComponent, default: []].append(fileURL)
            }
        }

        for txtpURL in txtpFiles {
            guard let contents = try? String(contentsOf: txtpURL, encoding: .utf8) else { continue }
            for rawLine in contents.split(whereSeparator: \.isNewline) {
                let reference = rawLine
                    .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !reference.isEmpty,
                      !reference.hasPrefix("/"),
                      !reference.contains(".."),
                      let leafName = reference.split(separator: "/").last.map(String.init),
                      let candidates = filesByLeafName[leafName],
                      candidates.count == 1 else {
                    continue
                }

                let aliasURL = txtpURL.deletingLastPathComponent()
                    .appendingPathComponent(reference, isDirectory: false)
                guard !fileManager.fileExists(atPath: aliasURL.path) else { continue }
                try fileManager.createDirectory(
                    at: aliasURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.linkItem(at: candidates[0], to: aliasURL)
            }
        }
    }

    private static func materializedEntryURL(archiveURL: URL, entryPath: String) throws -> URL {
        let safeComponents = sanitizedEntryPathComponents(entryPath)
        guard let leaf = safeComponents.last else {
            throw ArchiveError.invalidEntryPath(entryPath)
        }

        var destinationURL = archiveCacheURL(for: archiveURL)
        for component in safeComponents.dropLast() {
            destinationURL.appendPathComponent(component, isDirectory: true)
        }
        destinationURL.appendPathComponent(leaf, isDirectory: false)
        return destinationURL
    }

    private static func normalizedEntryPaths(_ entryPaths: [String]) throws -> [String] {
        let normalizedPaths = try Array(Set(entryPaths.map { entryPath in
            let normalized = normalizeEntryPath(entryPath)
            guard !normalized.isEmpty,
                  isSafeEntryPath(normalized) else {
                throw ArchiveError.invalidEntryPath(entryPath)
            }
            return normalized
        })).sorted()
        guard !normalizedPaths.isEmpty else {
            throw ArchiveError.invalidEntryPath("")
        }
        return normalizedPaths
    }

    private static func extractEntries(
        from archiveURL: URL,
        entryPaths: [String],
        into destinationURL: URL
    ) throws {
        switch archiveKind(for: archiveURL) {
        case .rsn:
            _ = try runProcess(
                executable: try executable(named: "unar"),
                arguments: ["-q", "-f", "-D", "-o", destinationURL.path, archiveURL.path] + entryPaths
            )
        case .zip, .sevenZip:
            _ = try runProcess(
                executable: try executable(named: "7zz"),
                arguments: ["x", "-mmt=1", "-y", "-o\(destinationURL.path)", archiveURL.path] + entryPaths
            )
        case .tarZstandard:
            try extractTarZstandardEntries(
                from: archiveURL,
                entryPaths: entryPaths,
                into: destinationURL
            )
        }
    }

    static func archiveCacheURL(for archiveURL: URL) -> URL {
        let attributes = try? FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let archiveFileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let archiveModifiedAt = attributes?[.modificationDate] as? Date ?? .distantPast
        let archiveCacheKey = sha256Hex(
            archiveURL.standardizedFileURL.path
                + "|"
                + String(archiveFileSize)
                + "|"
                + String(archiveModifiedAt.timeIntervalSinceReferenceDate)
        )
        return materializationCacheRootURL().appendingPathComponent(archiveCacheKey, isDirectory: true)
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

    private static func durableCacheRootURL() -> URL {
        cacheRootURL().appendingPathComponent("DurablePlayback", isDirectory: true)
    }

    private static func disposableCacheRootURL() -> URL {
        cacheRootURL().appendingPathComponent("DisposablePlayback", isDirectory: true)
    }

    private static func materializationCacheRootURL() -> URL {
        ArchiveCachePolicy.load().isEnabled ? durableCacheRootURL() : disposableCacheRootURL()
    }

    private static func prepareDurableCacheWrite(for archiveURL: URL) throws {
        let values = try materializationCacheRootURL().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        guard available >= ArchiveCachePolicy.requiredFreeBytes else {
            throw ArchiveError.insufficientStorage(requiredBytes: ArchiveCachePolicy.requiredFreeBytes)
        }
        try enforceDurableCacheLimit(preserving: archiveCacheURL(for: archiveURL))
    }

    private static func enforceDurableCacheLimit(preserving protectedRoot: URL) throws {
        let limit = ArchiveCachePolicy.load().activeLimitBytes
        let fileManager = FileManager.default
        let root = protectedRoot.deletingLastPathComponent()
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let protectedPath = protectedRoot.standardizedFileURL.path
        let activePath = playbackLease.path
        var candidates = entries.compactMap { entry -> (url: URL, bytes: Int64, date: Date)? in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            return (entry, directoryByteCount(entry), values?.contentModificationDate ?? .distantPast)
        }
        var total = candidates.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > limit else { return }
        candidates.sort { $0.date < $1.date }
        for candidate in candidates where total > limit {
            let candidatePath = candidate.url.standardizedFileURL.path
            guard candidatePath != protectedPath, candidatePath != activePath else { continue }
            try fileManager.removeItem(at: candidate.url)
            total -= candidate.bytes
        }
        if total > limit {
            throw ArchiveError.cacheLimitExceeded(limitBytes: limit)
        }
    }

    private static func touchCacheEntry(for archiveURL: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: archiveCacheURL(for: archiveURL).path
        )
    }

    private static func activatePlaybackLease(for archiveURL: URL) {
        playbackLease.replace(with: archiveCacheURL(for: archiveURL).standardizedFileURL.path)
    }

    private final class PlaybackLease: @unchecked Sendable {
        private let lock = NSLock()
        private var storedPath: String?

        var path: String? {
            lock.lock()
            defer { lock.unlock() }
            return storedPath
        }

        func replace(with path: String) {
            lock.lock()
            storedPath = path
            lock.unlock()
        }

        func clear() {
            lock.lock()
            storedPath = nil
            lock.unlock()
        }
    }

    private static func directoryByteCount(_ rootURL: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    private static func scanScratchRootURL() -> URL {
        cacheRootURL().appendingPathComponent("ScanScratch", isDirectory: true)
    }

    private static func makeScanScratchDirectory() throws -> URL {
        let rootURL = scanScratchRootURL()
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let scratchURL = rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: false)
        return scratchURL
    }

    private struct ArchiveListing {
        let entries: [String]
        let scanSignature: String?
    }

    private static func listEntries(in archiveURL: URL) throws -> ArchiveListing {
        switch archiveKind(for: archiveURL) {
        case .zip:
            let data = try runProcess(
                executable: try executable(named: "7zz"),
                arguments: ["l", "-mmt=1", "-slt", "-ba", archiveURL.path]
            )
            let report = String(decoding: data, as: UTF8.self)
            return ArchiveListing(
                entries: report
                .split(whereSeparator: \.isNewline)
                .compactMap { line in
                    let value = String(line)
                    guard value.hasPrefix("Path = ") else { return nil }
                    return String(value.dropFirst("Path = ".count))
                },
                scanSignature: report.isEmpty ? nil : "7zz-report:\n\(report)"
            )
        case .sevenZip:
            let data = try runProcess(
                executable: try executable(named: "7zz"),
                arguments: ["l", "-mmt=1", "-slt", "-ba", archiveURL.path]
            )
            let report = String(decoding: data, as: UTF8.self)
            return ArchiveListing(
                entries: report
                .split(whereSeparator: \.isNewline)
                .compactMap { line in
                    let value = String(line)
                    guard value.hasPrefix("Path = ") else { return nil }
                    return String(value.dropFirst("Path = ".count))
                },
                scanSignature: report.isEmpty ? nil : "7zz-report:\n\(report)"
            )
        case .rsn:
            let data = try runProcess(
                executable: try executable(named: "lsar"),
                arguments: ["-j", archiveURL.path]
            )
            guard
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let contents = object["lsarContents"] as? [[String: Any]]
            else {
                throw ArchiveError.processFailed(executable: "lsar", message: "invalid JSON listing")
            }
            return ArchiveListing(
                entries: contents.compactMap { $0["XADFileName"] as? String },
                scanSignature: nil
            )
        case .tarZstandard:
            let data = try runTarZstandardListing(archiveURL)
            return ArchiveListing(
                entries: tarListingEntryPaths(from: data),
                scanSignature: nil
            )
        }
    }

    private static func archiveKind(for archiveURL: URL) -> ArchiveKind {
        let archiveURL = archiveURL.standardizedFileURL
        if archiveURL.pathExtension.lowercased() == "zst",
           archiveURL.deletingPathExtension().pathExtension.lowercased() == "tar" {
            return .tarZstandard
        }
        switch archiveURL.pathExtension.lowercased() {
        case "zip": return .zip
        case "7z": return .sevenZip
        case "tzst": return .tarZstandard
        default: return .rsn
        }
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
        let rawTarURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tar", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: rawTarURL) }

        try runProcessWritingOutput(
            executable: try executable(named: "zstd"),
            arguments: ["-d", "-q", "-c", archiveURL.path],
            outputURL: rawTarURL
        )
        _ = try runProcess(
            executable: try executable(named: "tar"),
            arguments: ["-xf", rawTarURL.path, "-C", destinationURL.path]
        )
    }

    /// BSD tar's built-in Zstandard helper is unreliable for selected-member
    /// extraction. Decompress the container ourselves so every TAR+Zstandard
    /// path uses the same stable `tar` input.
    private static func extractTarZstandardEntries(
        from archiveURL: URL,
        entryPaths: [String],
        into destinationURL: URL
    ) throws {
        let rawTarURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tar", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: rawTarURL) }

        try runProcessWritingOutput(
            executable: try executable(named: "zstd"),
            arguments: ["-d", "-q", "-c", archiveURL.path],
            outputURL: rawTarURL
        )
        let literalPaths = entryPaths.filter { !containsTarOctalEscape($0) }
        if !literalPaths.isEmpty {
            _ = try runProcess(
                executable: try executable(named: "tar"),
                arguments: ["-xf", rawTarURL.path, "-C", destinationURL.path]
                    + tarMemberSelectionPatterns(literalPaths)
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
            try runProcessWritingOutput(
                executable: try executable(named: "tar"),
                arguments: ["-xOf", rawTarURL.path, "--null", "-T", selectionURL.path],
                outputURL: outputURL
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

    /// Turns BSD tar's byte stream into a displayable *and reversible* path.
    /// `String(decoding:as:)` silently replaces malformed UTF-8 with U+FFFD,
    /// losing the original byte before extraction can select it. Keep valid
    /// UTF-8 as-is and render only invalid bytes with BSD-tar-style octal.
    private static func tarListingEntryPaths(from data: Data) -> [String] {
        data.split(separator: 0x0A, omittingEmptySubsequences: true).map { line in
            var output = ""
            var index = line.startIndex
            while index < line.endIndex {
                var decoded: String?
                for length in 1...4 where line.distance(from: index, to: line.endIndex) >= length {
                    let end = line.index(index, offsetBy: length)
                    if let string = String(bytes: line[index..<end], encoding: .utf8),
                       string.utf8.count == length {
                        decoded = string
                        index = end
                        break
                    }
                }
                if let decoded {
                    output.append(decoded)
                } else {
                    output += String(format: "\\%03o", line[index])
                    index = line.index(after: index)
                }
            }
            return output
        }
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
        entryPaths.map { entryPath in
            entryPath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "*", with: "\\*")
                .replacingOccurrences(of: "?", with: "\\?")
                .replacingOccurrences(of: "[", with: "\\[")
        }
    }

    /// BSD tar's automatic Zstandard helper exits spuriously when many archive
    /// listings run at once. Keep the same fully concurrent scanner behavior,
    /// but connect the reliable `zstd` binary to tar explicitly instead.
    private static func runTarZstandardListing(_ archiveURL: URL) throws -> Data {
        while processGate.wait(timeout: .now() + .milliseconds(100)) != .success {
            if Task.isCancelled { throw CancellationError() }
        }
        defer { processGate.signal() }

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

        let decompressorErrors = ProcessOutputCollector()
        let listerErrors = ProcessOutputCollector()
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
        let decompressorReportedBrokenPipe = isExpectedTarListingBrokenPipe(
            exitStatus: decompressor.terminationStatus,
            terminationReason: decompressor.terminationReason,
            stderr: decompressorErrorText
        )
        let decompressorSucceeded = decompressor.terminationStatus == 0
            || (decompressor.terminationReason == .uncaughtSignal
                && decompressor.terminationStatus == SIGPIPE)
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
        return try Data(contentsOf: outputURL)
    }

    static func isExpectedTarListingBrokenPipe(
        exitStatus: Int32,
        terminationReason: Process.TerminationReason,
        stderr: String
    ) -> Bool {
        terminationReason == .exit
            && exitStatus == 70
            && stderr.localizedCaseInsensitiveContains("write error")
            && stderr.localizedCaseInsensitiveContains("broken pipe")
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

    private static func sanitizedEntryPathComponents(_ entryPath: String) -> [String] {
        normalizeEntryPath(entryPath)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func isSafeEntryPath(_ entryPath: String) -> Bool {
        !normalizeEntryPath(entryPath)
            .split(separator: "/")
            .contains("..")
    }

    private static func normalizeEntryPath(_ entryPath: String) -> String {
        entryPath
            // BSD tar represents an otherwise non-UTF-8 member byte as an
            // octal escape (for example `\\255`). That backslash is part of
            // its reversible listing syntax, not a Windows path separator.
            .replacingOccurrences(of: "\\", with: containsTarOctalEscape(entryPath) ? "\\" : "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func runProcess(
        executable: String,
        arguments: [String]
    ) throws -> Data {
        while processGate.wait(timeout: .now() + .milliseconds(100)) != .success {
            if Task.isCancelled {
                throw CancellationError()
            }
        }
        defer { processGate.signal() }

        // Listing is bounded tightly, but a valid extraction must be allowed
        // to decompress a large solid TAR+Zstandard source. The scan pipeline
        // uses the same 10-minute extraction boundary.
        let executableName = URL(fileURLWithPath: executable).lastPathComponent
        let isExtraction = executableName == "unar"
            || arguments.first == "x"
            || arguments.contains("-xf")
        let processTimeout = isExtraction ? archiveExtractionTimeout : archiveListingTimeout
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = archiveProcessEnvironment()

        let outputURL = try processOutputURL()
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        let stderr = Pipe()
        process.standardOutput = outputHandle
        process.standardError = stderr

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        try process.run()
        defer { process.terminationHandler = nil }
        let errorReadHandle = stderr.fileHandleForReading
        try stderr.fileHandleForWriting.close()

        let errorCollector = ProcessOutputCollector()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = errorReadHandle.readDataToEndOfFile()
            try? errorReadHandle.close()
            errorCollector.set(data)
            readers.leave()
        }

        do {
            try waitForProcess(
                process,
                completion: completion,
                executable: executable,
                timeout: processTimeout
            )
        } catch {
            readers.wait()
            throw error
        }
        readers.wait()
        try outputHandle.close()

        let errorData = errorCollector.value
        guard process.terminationStatus == 0 else {
            let errorText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveError.processFailed(
                executable: URL(fileURLWithPath: executable).lastPathComponent,
                message: errorText.isEmpty ? "exit code \(process.terminationStatus)" : errorText
            )
        }

        return try Data(contentsOf: outputURL)
    }

    private static func runProcessWritingOutput(
        executable: String,
        arguments: [String],
        outputURL: URL
    ) throws {
        while processGate.wait(timeout: .now() + .milliseconds(100)) != .success {
            if Task.isCancelled { throw CancellationError() }
        }
        defer { processGate.signal() }

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = archiveProcessEnvironment()
        process.standardOutput = outputHandle

        let stderr = Pipe()
        process.standardError = stderr
        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        try process.run()
        defer { process.terminationHandler = nil }
        let errorReadHandle = stderr.fileHandleForReading
        try stderr.fileHandleForWriting.close()

        let errorCollector = ProcessOutputCollector()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = errorReadHandle.readDataToEndOfFile()
            try? errorReadHandle.close()
            errorCollector.set(data)
            readers.leave()
        }

        do {
            try waitForProcess(
                process,
                completion: completion,
                executable: executable,
                timeout: archiveExtractionTimeout
            )
        } catch {
            readers.wait()
            throw error
        }
        readers.wait()
        try outputHandle.close()

        guard process.terminationStatus == 0 else {
            let errorText = String(decoding: errorCollector.value, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveError.processFailed(
                executable: URL(fileURLWithPath: executable).lastPathComponent,
                message: errorText.isEmpty ? "exit code \(process.terminationStatus)" : errorText
            )
        }
    }

    private static func processOutputURL() throws -> URL {
        let directoryURL = cacheRootURL()
            .appendingPathComponent("Process", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL.appendingPathComponent(
            "CocoaSpice-process-\(UUID().uuidString)",
            isDirectory: false
        )
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
        let deadline = Date().addingTimeInterval(timeout)
        while completion.wait(timeout: .now() + .milliseconds(100)) != .success {
            if Task.isCancelled {
                process.terminate()
                process.waitUntilExit()
                throw CancellationError()
            }
            if Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                throw ArchiveError.processFailed(
                    executable: URL(fileURLWithPath: executable).lastPathComponent,
                    message: "timed out after \(Int(timeout)) seconds"
                )
            }
        }
    }
}

private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func set(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }
}
