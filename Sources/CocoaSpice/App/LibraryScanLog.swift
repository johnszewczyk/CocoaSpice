import Foundation

final class ScanIssueCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ issue: String) {
        lock.lock()
        values.append(issue)
        lock.unlock()
    }

    func append(contentsOf issues: [String]) {
        lock.lock()
        values.append(contentsOf: issues)
        lock.unlock()
    }

    var issues: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

enum LibraryScanLogStore {
    static let maximumReadBytes = 2 * 1_024 * 1_024
    static let maximumRenderedIssues = 2_000
    static func fileURL(rootID: Int64) -> URL {
        let baseURL =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ))
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("CocoaSpice", isDirectory: true)
            .appendingPathComponent("ScanLogs", isDirectory: true)
            .appendingPathComponent("root-\(rootID).log", isDirectory: false)
    }

    static func exists(rootID: Int64) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(rootID: rootID).path)
    }

    static func read(rootID: Int64) -> [String] {
        let url = fileURL(rootID: rootID)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return []
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumReadBytes),
              let contents = String(data: data, encoding: .utf8) else {
            return ["Unable to read scan log."]
        }
        var issues = contents.split(whereSeparator: \.isNewline).map(String.init)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize > maximumReadBytes {
            issues.append("Log truncated after \(maximumReadBytes / 1_024 / 1_024) MiB to keep this window responsive.")
        }
        if issues.count > maximumRenderedIssues {
            issues = Array(issues.prefix(maximumRenderedIssues - 1))
            issues.append("Log truncated after \(maximumRenderedIssues) issues to keep this window responsive.")
        }
        return issues
    }

    static func write(
        rootID: Int64,
        issues: [String]
    ) {
        let fileURL = fileURL(rootID: rootID)
        if issues.isEmpty {
            remove(rootID: rootID)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let boundedIssues = Array(issues.prefix(maximumRenderedIssues - 1))
                + (issues.count > maximumRenderedIssues
                    ? ["Log truncated after \(maximumRenderedIssues) issues."]
                    : [])
            try boundedIssues.joined(separator: "\n").appending("\n").write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            // Scan diagnostics must never interfere with the scan itself.
        }
    }

    static func remove(rootID: Int64) {
        try? FileManager.default.removeItem(at: fileURL(rootID: rootID))
    }
}
