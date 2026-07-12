import CryptoKit
import Dispatch
import Foundation

enum ZipArchiveSupport {
    static let supportedArchiveExtensions: Set<String> = ["zip", "7z", "rsn"]
    /// Archive commands are deliberately one-thread-per-process. The scanner
    /// fans those processes across the machine instead of allowing every 7zz
    /// process to spawn its own full-width worker pool.
    // Leave one cooperative runtime thread free while bounded extractor jobs
    // are running. Eight simultaneous archive jobs on this host deadlock;
    // seven complete concurrently.
    static let archiveProcessConcurrency = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    private static let processGate = DispatchSemaphore(value: archiveProcessConcurrency)

    private enum ArchiveKind {
        case zip
        case sevenZip
        case rsn
    }

    struct ArchiveEntry: Hashable, Sendable {
        let archiveURL: URL
        let entryPath: String
    }

    enum ArchiveError: LocalizedError {
        case unsupportedArchive(URL)
        case processFailed(executable: String, message: String)
        case invalidEntryPath(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedArchive(let url):
                return "Unsupported archive format: \(url.lastPathComponent)"
            case .processFailed(let executable, let message):
                return "\(executable) failed: \(message)"
            case .invalidEntryPath(let path):
                return "Invalid archive entry path: \(path)"
            }
        }
    }

    static func canHandle(_ url: URL) -> Bool {
        supportedArchiveExtensions.contains(url.pathExtension.lowercased())
    }

    static func listPlayableEntries(
        in archiveURL: URL,
        supportedExtensions: Set<String>
    ) throws -> [ArchiveEntry] {
        let archiveURL = archiveURL.standardizedFileURL
        guard canHandle(archiveURL) else {
            throw ArchiveError.unsupportedArchive(archiveURL)
        }

        let listing = try listEntries(in: archiveURL)

        return listing
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
    }

    static func materializePlayableFile(for track: TrackItem) throws -> URL {
        switch track.source {
        case .file(let url):
            return url
        case .zipEntry(let archiveURL, let entryPath):
            let extensionName = URL(fileURLWithPath: entryPath).pathExtension.lowercased()
            if extensionName == "usf" || extensionName == "miniusf" {
                let setURL = try materializeArchive(at: archiveURL)
                try prepareLazyUSFDependencies(in: setURL)
                return archiveMemberURL(in: setURL, entryPath: entryPath)
            }
            return try materializeEntry(archiveURL: archiveURL, entryPath: entryPath)
        }
    }

    static func materializeEntry(archiveURL: URL, entryPath: String) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        let normalizedEntryPath = normalizeEntryPath(entryPath)
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
            return destinationURL
        }

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
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    static func materializeArchive(at archiveURL: URL) throws -> URL {
        let archiveURL = archiveURL.standardizedFileURL
        let rootURL = cacheRootURL().appendingPathComponent(
            sha256Hex(archiveURL.path + "|" + String(((try? archiveURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast).timeIntervalSinceReferenceDate)),
            isDirectory: true
        ).appendingPathComponent("set", isDirectory: true)
        let completionURL = rootURL.appendingPathComponent(".complete", isDirectory: false)
        if FileManager.default.fileExists(atPath: completionURL.path) { return rootURL }

        let stagingURL = rootURL.deletingLastPathComponent().appendingPathComponent(".set-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stagingURL) }
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        switch archiveKind(for: archiveURL) {
        case .rsn:
            _ = try runProcess(executable: try executable(named: "unar"), arguments: ["-q", "-f", "-o", stagingURL.path, archiveURL.path])
        case .zip, .sevenZip:
            _ = try runProcess(executable: try executable(named: "7zz"), arguments: ["x", "-mmt=1", "-y", "-o\(stagingURL.path)", archiveURL.path])
        }
        try Data().write(to: stagingURL.appendingPathComponent(".complete"))
        try FileManager.default.createDirectory(at: rootURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.moveItem(at: stagingURL, to: rootURL)
        }
        return rootURL
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

    private static func materializedEntryURL(archiveURL: URL, entryPath: String) throws -> URL {
        let archiveModifiedAt =
            (try? archiveURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        let archiveCacheKey = sha256Hex(
            archiveURL.path + "|" + String(archiveModifiedAt.timeIntervalSinceReferenceDate)
        )

        let safeComponents = sanitizedEntryPathComponents(entryPath)
        guard let leaf = safeComponents.last else {
            throw ArchiveError.invalidEntryPath(entryPath)
        }

        var destinationURL = cacheRootURL()
            .appendingPathComponent(archiveCacheKey, isDirectory: true)
        for component in safeComponents.dropLast() {
            destinationURL.appendPathComponent(component, isDirectory: true)
        }
        destinationURL.appendPathComponent(leaf, isDirectory: false)
        return destinationURL
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

    private static func listEntries(in archiveURL: URL) throws -> [String] {
        switch archiveKind(for: archiveURL) {
        case .zip:
            let data = try runProcess(
                executable: try executable(named: "7zz"),
                arguments: ["l", "-mmt=1", "-slt", "-ba", archiveURL.path]
            )
            return String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .compactMap { line in
                    let value = String(line)
                    guard value.hasPrefix("Path = ") else { return nil }
                    return String(value.dropFirst("Path = ".count))
                }
        case .sevenZip:
            let data = try runProcess(
                executable: try executable(named: "7zz"),
                arguments: ["l", "-mmt=1", "-slt", "-ba", archiveURL.path]
            )
            return String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .compactMap { line in
                    let value = String(line)
                    guard value.hasPrefix("Path = ") else { return nil }
                    return String(value.dropFirst("Path = ".count))
                }
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
            return contents.compactMap { $0["XADFileName"] as? String }
        }
    }

    private static func archiveKind(for archiveURL: URL) -> ArchiveKind {
        switch archiveURL.pathExtension.lowercased() {
        case "zip": return .zip
        case "7z": return .sevenZip
        default: return .rsn
        }
    }

    private static func executable(named name: String) throws -> String {
        let environmentKey: String
        switch name {
        case "7zz": environmentKey = "COCOASPICE_7Z_BINARY"
        case "unar": environmentKey = "COCOASPICE_UNAR_BINARY"
        case "lsar": environmentKey = "COCOASPICE_LSAR_BINARY"
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
            message: "Install 7-Zip and unar, then retry archive playback."
        )
    }

    private static func sanitizedEntryPathComponents(_ entryPath: String) -> [String] {
        normalizeEntryPath(entryPath)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func normalizeEntryPath(_ entryPath: String) -> String {
        entryPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
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

        let processTimeout: TimeInterval = 30
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CocoaSpice-process-\(UUID().uuidString)", isDirectory: false)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        let stderr = Pipe()
        process.standardOutput = outputHandle
        process.standardError = stderr

        try process.run()

        let errorCollector = ProcessOutputCollector()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errorCollector.set(stderr.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        let deadline = Date().addingTimeInterval(processTimeout)
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                process.waitUntilExit()
                readers.wait()
                throw CancellationError()
            }
            if Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                readers.wait()
                throw ArchiveError.processFailed(
                    executable: URL(fileURLWithPath: executable).lastPathComponent,
                    message: "timed out after \(Int(processTimeout)) seconds"
                )
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        readers.wait()

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
        process.standardOutput = outputHandle

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()

        let errorCollector = ProcessOutputCollector()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errorCollector.set(stderr.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        let deadline = Date().addingTimeInterval(30)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                readers.wait()
                if Task.isCancelled { throw CancellationError() }
                throw ArchiveError.processFailed(
                    executable: URL(fileURLWithPath: executable).lastPathComponent,
                    message: "timed out after 30 seconds"
                )
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        readers.wait()

        guard process.terminationStatus == 0 else {
            let errorText = String(decoding: errorCollector.value, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveError.processFailed(
                executable: URL(fileURLWithPath: executable).lastPathComponent,
                message: errorText.isEmpty ? "exit code \(process.terminationStatus)" : errorText
            )
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
