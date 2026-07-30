import Foundation

enum SPCFileScanner {
    static let supportedExtensions = PlaybackFormatRegistry.supportedExtensions

    static func childFolders(in folderURL: URL) -> [SidebarFolder] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { isDirectory($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { SidebarFolder(url: $0, hasChildren: true) }
    }

    static func playlist(for folderURL: URL) -> [TrackItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { PlaybackFormatRegistry.admits(fileURL: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { TrackItem(url: $0) }
    }

    static func searchSidebarItems(in rootURL: URL, query: String, limit: Int = 250) -> [SidebarSearchItem] {
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var folders: [SidebarSearchItem] = []
        var tracks: [SidebarSearchItem] = []

        for case let url as URL in enumerator {
            let haystack = url.path
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .lowercased()
            guard terms.allSatisfy({ haystack.contains($0) }) else { continue }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                folders.append(SidebarSearchItem(url: url, kind: .folder, primaryTextOverride: nil, secondaryTextOverride: nil))
            } else if values?.isRegularFile == true,
                      PlaybackFormatRegistry.admits(fileURL: url) {
                let track = TrackItem(url: url)
                tracks.append(
                    SidebarSearchItem(
                        url: url,
                        kind: .track,
                        track: track,
                        primaryTextOverride: nil,
                        secondaryTextOverride: nil
                    )
                )
            }

            if folders.count + tracks.count >= limit {
                break
            }
        }

        folders.sort(by: { lhs, rhs in
            let parent = lhs.parentPath.localizedStandardCompare(rhs.parentPath)
            if parent != .orderedSame { return parent == .orderedAscending }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        })
        tracks.sort(by: { lhs, rhs in
            let parent = lhs.parentPath.localizedStandardCompare(rhs.parentPath)
            if parent != .orderedSame { return parent == .orderedAscending }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        })
        return Array((folders + tracks).prefix(limit))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
