import Foundation

/// Async permits keep scanner backpressure off the main actor and avoid the
/// blocking semaphore pattern that caused the previous scanner to stall.
actor ScanResourceScheduler {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) {
        availablePermits = max(1, permits)
    }

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            availablePermits += 1
        }
    }

    func withPermit<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            // Do not run a synchronous extractor or decoder while this actor
            // owns the scheduler executor. Doing so turns every permit into a
            // single serial queue and leaves all scan workers appearing stuck
            // behind the first archive.
            let task = Task.detached(priority: .utility, operation: operation)
            let result = try await withTaskCancellationHandler(
                operation: { try await task.value },
                onCancel: { task.cancel() }
            )
            release()
            return result
        } catch {
            release()
            throw error
        }
    }
}
