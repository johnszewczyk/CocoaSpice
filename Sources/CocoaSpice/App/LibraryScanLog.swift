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
        guard let contents = try? String(contentsOf: fileURL(rootID: rootID), encoding: .utf8) else {
            return []
        }
        return contents.split(whereSeparator: \.isNewline).map(String.init)
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
            try issues.joined(separator: "\n").appending("\n").write(
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
