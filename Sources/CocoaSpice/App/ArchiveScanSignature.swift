import Foundation

/// Supplies a durable archive identity without listing or extracting archive
/// members. This deliberately covers only the common, broadly supported
/// containers CocoaSpice scans: ZIP, 7z, and TAR+Zstandard.
enum ArchiveScanSignature {
    static func supports(_ url: URL) -> Bool {
        let url = url.standardizedFileURL
        switch url.pathExtension.lowercased() {
        case "zip", "7z", "tzst":
            return true
        case "zst":
            return url.deletingPathExtension().pathExtension.lowercased() == "tar"
        default:
            return false
        }
    }

    static func enrich(_ candidate: ScanCandidate) async -> ScanCandidate {
        guard candidate.identity.archiveEntry == nil,
              candidate.fingerprint.contentSignature == nil,
              supports(candidate.sourceURL) else {
            return candidate
        }

        let signature = await Task.detached(priority: .utility) {
            try? ZipArchiveSupport.scanSignature(for: candidate.sourceURL)
        }.value
        return ScanCandidate(
            identity: candidate.identity,
            fingerprint: ScanFingerprint(
                fileSize: candidate.fingerprint.fileSize,
                modifiedAt: candidate.fingerprint.modifiedAt,
                contentSignature: signature
            ),
            sourceURL: candidate.sourceURL,
            route: candidate.route
        )
    }

}
