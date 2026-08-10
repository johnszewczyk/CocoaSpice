import Foundation

/// Filesystem ownership rules for archive playback material. Keeping these
/// operations independent from the archive extractors makes their deletion
/// and LRU behavior testable against an isolated cache root.
struct ArchiveCacheLifecycle {
    struct Recovery: Sendable {
        let rootCount: Int
        let byteCount: Int64
    }

    let cacheRootURL: URL

    var durableRootURL: URL {
        cacheRootURL.appendingPathComponent("DurablePlayback", isDirectory: true)
    }

    var disposableRootURL: URL {
        cacheRootURL.appendingPathComponent("DisposablePlayback", isDirectory: true)
    }

    var scanScratchRootURL: URL {
        cacheRootURL.appendingPathComponent("ScanScratch", isDirectory: true)
    }

    func clearAllPlaybackMaterialization() throws {
        let fileManager = FileManager.default
        for rootURL in [durableRootURL, disposableRootURL] where fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
    }

    func discardDisposablePlaybackMaterialization() {
        try? FileManager.default.removeItem(at: disposableRootURL)
    }

    /// Removes only material CocoaSpice can prove is disposable: interrupted
    /// scans, cache-off playback, obsolete pre-policy entries, and hidden
    /// durable extraction staging directories.
    func reclaimAbandonedMaterialization() -> Recovery {
        let fileManager = FileManager.default
        var count = 0
        var bytes: Int64 = 0

        func discard(_ root: URL) {
            guard fileManager.fileExists(atPath: root.path) else { return }
            let rootBytes = directoryByteCount(root)
            guard (try? fileManager.removeItem(at: root)) != nil else { return }
            bytes += rootBytes
            count += 1
        }

        discard(scanScratchRootURL)
        discard(disposableRootURL)

        let retainedNames: Set<String> = ["DurablePlayback", "ScanScratch", "DisposablePlayback"]
        if let children = try? fileManager.contentsOfDirectory(at: cacheRootURL, includingPropertiesForKeys: nil) {
            for child in children where !retainedNames.contains(child.lastPathComponent) {
                discard(child)
            }
        }

        if let children = try? fileManager.contentsOfDirectory(at: durableRootURL, includingPropertiesForKeys: nil) {
            for child in children where child.lastPathComponent.hasPrefix(".") {
                discard(child)
            }
        }
        return Recovery(rootCount: count, byteCount: bytes)
    }

    /// Evicts least-recently-used materialization roots. The pending write
    /// and currently playing root are never evicted. Returns false only when
    /// those protected roots alone exceed the configured limit.
    func pruneDurableMaterialization(
        maximumBytes: Int64,
        preserving protectedRoot: URL,
        activePlaybackRoot: URL?
    ) throws -> Bool {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: durableRootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return true
        }
        let protectedPath = protectedRoot.standardizedFileURL.path
        let activePath = activePlaybackRoot?.standardizedFileURL.path
        var candidates = entries.compactMap { entry -> (url: URL, bytes: Int64, date: Date)? in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            return (entry, directoryByteCount(entry), values?.contentModificationDate ?? .distantPast)
        }
        var total = candidates.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > maximumBytes else { return true }

        candidates.sort { $0.date < $1.date }
        for candidate in candidates where total > maximumBytes {
            let candidatePath = candidate.url.standardizedFileURL.path
            guard candidatePath != protectedPath, candidatePath != activePath else { continue }
            try fileManager.removeItem(at: candidate.url)
            total -= candidate.bytes
        }
        return total <= maximumBytes
    }

    private func directoryByteCount(_ root: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var bytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            bytes += Int64(values.fileSize ?? 0)
        }
        return bytes
    }
}
