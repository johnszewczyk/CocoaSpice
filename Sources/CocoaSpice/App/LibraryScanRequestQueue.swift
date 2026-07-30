import Foundation

/// A FIFO of requested library scans, kept independent from scan execution.
///
/// Requests hold root identities rather than stale root values, allowing path
/// settings to change while another scan is in progress.
struct LibraryScanRequest: Sendable {
    let rootIDs: [Int64]
    let mode: ScanMode

    init(roots: [LibraryScanRoot], mode: ScanMode) {
        rootIDs = roots.map(\.id)
        self.mode = mode
    }
}

@MainActor
final class LibraryScanRequestQueue {
    private var requests: [LibraryScanRequest] = []

    var count: Int {
        requests.count
    }

    func enqueue(roots: [LibraryScanRoot], mode: ScanMode) {
        requests.append(LibraryScanRequest(roots: roots, mode: mode))
    }

    func dequeue() -> LibraryScanRequest? {
        guard !requests.isEmpty else { return nil }
        return requests.removeFirst()
    }

    func clear() {
        requests.removeAll()
    }
}
