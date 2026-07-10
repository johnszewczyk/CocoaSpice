import Foundation

enum DatabaseSidebarPresentation {
    private static let scanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func selectionStatusText(for item: DatabaseGameItem) -> String {
        "\(item.displayName) • \(item.trackCount) track\(item.trackCount == 1 ? "" : "s")"
    }

    static func filterGameItems(_ items: [DatabaseGameItem], query: String) -> [DatabaseGameItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return items }

        let terms = trimmedQuery
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else { return items }

        return items.filter { item in
            terms.allSatisfy { item.searchableName.contains($0) }
        }
    }

    static func disambiguateGameItems(_ items: [DatabaseGameItem]) -> [DatabaseGameItem] {
        let duplicateNames = Set(
            Dictionary(grouping: items, by: \.name)
                .filter { $0.value.count > 1 }
                .keys
        )

        return items.map { item in
            guard duplicateNames.contains(item.name) else { return item }
            let detail = item.systemName.isEmpty ? "Unknown System" : item.systemName
            return DatabaseGameItem(
                name: item.name,
                systemName: item.systemName,
                trackCount: item.trackCount,
                displayName: "\(item.name) (\(detail))"
            )
        }
    }

    static func scanRootStatusText(_ root: LibraryScanRoot, order: Int) -> String {
        if let error = root.lastScanError, !error.isEmpty {
            return error
        }

        if let lastScanCompletedAt = root.lastScanCompletedAt {
            let count = root.lastScanTrackCount == 0 ? "0 Files" : "\(root.lastScanTrackCount) Files"
            return "Last Scan \(scanDateFormatter.string(from: lastScanCompletedAt)) • \(count)"
        }

        return "Not scanned"
    }
}
