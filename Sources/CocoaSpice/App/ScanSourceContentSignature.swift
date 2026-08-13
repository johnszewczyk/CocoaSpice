import CryptoKit
import Foundation

enum ScanSourceContentSignature {
    private static let fullHashThreshold: Int64 = 1_048_576
    private static let sampleSize = 65_536

    static func enrich(_ candidate: ScanCandidate) async -> ScanCandidate {
        guard candidate.identity.archiveEntry == nil,
              !ZipArchiveSupport.canHandle(candidate.sourceURL),
              let signature = try? signature(for: candidate.sourceURL, size: candidate.fingerprint.fileSize) else {
            return candidate
        }
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

    private static func signature(for fileURL: URL, size: Int64) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        hasher.update(data: Data("cocoaspice-content-v1\0".utf8))

        if size <= fullHashThreshold {
            hasher.update(data: try handle.readToEnd() ?? Data())
        } else {
            let offsets: [UInt64] = [
                0,
                UInt64(max(0, (size - Int64(sampleSize)) / 2)),
                UInt64(max(0, size - Int64(sampleSize)))
            ]
            for offset in offsets {
                try handle.seek(toOffset: offset)
                hasher.update(data: try handle.read(upToCount: sampleSize) ?? Data())
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
