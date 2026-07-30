import Foundation

enum ScanFilesystemDiscovery {
    static func discover(
        rootID: Int64,
        rootURL: URL,
        registry: ScanPluginRegistry
    ) async -> [ScanCandidate] {
        await Task.detached(priority: .utility) {
            var candidates: [ScanCandidate] = []
            walk(rootID: rootID, folderURL: rootURL.standardizedFileURL, registry: registry, candidates: &candidates)
            return candidates.sorted {
                $0.identity.path.localizedStandardCompare($1.identity.path) == .orderedAscending
            }
        }.value
    }

    private static func walk(
        rootID: Int64,
        folderURL: URL,
        registry: ScanPluginRegistry,
        candidates: inout [ScanCandidate]
    ) {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // `enumerator(at:includingPropertiesForKeys:)` prefetches these
        // attributes in one traversal. The old recursive implementation
        // sorted every directory and fetched each file's metadata twice.
        // We retain deterministic output with the single final sort in
        // `discover`, without the repeated filesystem round trips.
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ])
            guard values?.isRegularFile == true else { continue }
            let isArchive = ZipArchiveSupport.canHandle(child)
            let extensionName = child.pathExtension.lowercased()
            guard isArchive || registry.route(for: extensionName) != nil else { continue }
            let fingerprint = ScanFingerprint(
                fileSize: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate ?? .distantPast
            )
            candidates.append(
                ScanCandidate(
                    identity: ScanItemIdentity(rootID: rootID, path: child.path, archiveEntry: nil),
                    fingerprint: fingerprint,
                    sourceURL: child,
                    route: registry.route(for: extensionName)
                )
            )
        }
    }
}
