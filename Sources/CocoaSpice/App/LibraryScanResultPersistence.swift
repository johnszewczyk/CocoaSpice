import Foundation

extension LibraryDatabase {
    func persistScanResult(_ result: ScanPipelineResult) throws {
        switch result {
        case .success(let candidate, let inspection):
            let item = ScanInventoryItem(
                identity: candidate.identity,
                fingerprint: candidate.fingerprint,
                state: .successful,
                route: inspection.route
            )
            try upsertScanItem(item)

        case .archiveCompleted(let candidate):
            let item = ScanInventoryItem(
                identity: candidate.identity,
                fingerprint: candidate.fingerprint,
                state: .successful,
                route: candidate.route
            )
            try upsertScanItem(item)

        case .unsupported(let candidate):
            let item = ScanInventoryItem(
                identity: candidate.identity,
                fingerprint: candidate.fingerprint,
                state: .unsupported,
                route: candidate.route
            )
            try upsertScanItem(item)

        case .failure(let failure):
            let item = ScanInventoryItem(
                identity: failure.identity,
                fingerprint: failure.fingerprint,
                state: failure.message == "Cancelled" ? .cancelled : .failed,
                route: failure.route
            )
            try upsertScanItem(item, failure: failure.message == "Cancelled" ? nil : failure)
        }
    }
}
