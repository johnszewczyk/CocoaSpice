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
        var lastReportedAt = Date.distantPast

        for (index, source) in sources.enumerated() {
            guard !Task.isCancelled else { break }
            if !FileManager.default.fileExists(atPath: source.path) {
                missing.append(source)
            }
            let current = index + 1
            let now = Date()
            if current == 1
                || current == sources.count
                || current.isMultiple(of: 25)
                || now.timeIntervalSince(lastReportedAt) >= 0.5 {
                lastReportedAt = now
                progress(current, sources.count, source.path)
            }
            // This is already detached from the main actor. Yielding between
            // batches prevents a very large link test from monopolizing a
            // cooperative worker executor.
            if current.isMultiple(of: 256) {
                await Task.yield()
            }
        }

        return LibraryIntegrityResult(
            checkedCount: sources.count,
            missingSources: missing
        )
    }
}
