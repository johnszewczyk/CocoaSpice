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
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for child in children.sorted(by: { $0.path < $1.path }) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                walk(rootID: rootID, folderURL: child, registry: registry, candidates: &candidates)
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let isArchive = ZipArchiveSupport.canHandle(child)
            let extensionName = child.pathExtension.lowercased()
            guard isArchive || registry.route(for: extensionName) != nil else { continue }
            let resourceValues = try? child.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fingerprint = ScanFingerprint(
                fileSize: Int64(resourceValues?.fileSize ?? 0),
                modifiedAt: resourceValues?.contentModificationDate ?? .distantPast
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
