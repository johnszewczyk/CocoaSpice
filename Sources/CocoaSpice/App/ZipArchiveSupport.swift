import CryptoKit
import Foundation

enum ZipArchiveSupport {
    static let supportedArchiveExtensions: Set<String> = ["zip"]

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

        let listingData = try runProcess(
            executable: "/usr/bin/zipinfo",
            arguments: ["-1", archiveURL.path]
        )
        let listing = String(decoding: listingData, as: UTF8.self)

        return listing
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { rawEntry in
                let normalized = normalizeEntryPath(rawEntry)
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

        let data = try runProcess(
            executable: "/usr/bin/unzip",
            arguments: ["-p", archiveURL.path, normalizedEntryPath]
        )

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errorText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveError.processFailed(
                executable: URL(fileURLWithPath: executable).lastPathComponent,
                message: errorText.isEmpty ? "exit code \(process.terminationStatus)" : errorText
            )
        }

        return output
    }
}
