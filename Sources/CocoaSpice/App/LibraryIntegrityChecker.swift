import Foundation

struct LibraryIndexedSource: Hashable, Sendable {
    let rootID: Int64
    let path: String
    let archiveEntry: String?
}

struct LibraryIntegrityResult: Sendable {
    let checkedCount: Int
    let missingSources: [LibraryIndexedSource]
}

enum LibraryIntegrityChecker {
    static func check(
        sources: [LibraryIndexedSource],
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async -> LibraryIntegrityResult {
        var missing: [LibraryIndexedSource] = []

        for (index, source) in sources.enumerated() {
            guard !Task.isCancelled else { break }
            if !FileManager.default.fileExists(atPath: source.path) {
                missing.append(source)
            }
            progress(index + 1, sources.count, source.path)
        }

        return LibraryIntegrityResult(
            checkedCount: sources.count,
            missingSources: missing
        )
    }
}
