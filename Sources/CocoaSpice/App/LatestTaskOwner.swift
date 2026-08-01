import Foundation

/// Owns the most recent task in an independently cancellable UI workflow.
///
/// Its generation changes on replacement, completion, and cancellation so
/// late asynchronous callbacks cannot publish stale state.
@MainActor
final class LatestTaskOwner {
    private var task: Task<Void, Never>?
    private var generation = 0
    private(set) var isActive = false

    func begin() -> Int {
        task?.cancel()
        task = nil
        generation &+= 1
        isActive = true
        return generation
    }

    func install(_ task: Task<Void, Never>, generation: Int) {
        guard isCurrent(generation) else {
            task.cancel()
            return
        }
        self.task = task
    }

    func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation
    }

    func finish(generation: Int) {
        guard isCurrent(generation) else { return }
        task = nil
        isActive = false
        self.generation &+= 1
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        isActive = false
    }
}
