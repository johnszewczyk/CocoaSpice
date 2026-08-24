import FavoriteStoreCore
import FavoriteTrackCore
import Foundation
import Observation

@MainActor @Observable
final class FavoritesCoordinator {
    private(set) var records: [FavoriteTrackSnapshot] = []
    private(set) var presentationRevision = 0
    private var store: FavoriteStore?
    private var storeRevision: Int64 = -1

    func restore() throws {
        let store = try FavoriteStore()
        self.store = store
        records = try store.snapshots()
        storeRevision = try store.revision()
        presentationRevision &+= 1
    }

    func toggle(_ snapshots: [FavoriteTrackSnapshot]) throws -> FavoriteStoreMutation {
        guard let store else { throw FavoritesCoordinatorError.storeUnavailable }
        let mutation = try store.toggle(snapshots)
        records = try store.snapshots()
        storeRevision = mutation.revision
        presentationRevision &+= 1
        return mutation
    }

    func refreshIfChanged() throws -> Bool {
        guard let store else { return false }
        let revision = try store.revision()
        guard revision != storeRevision else { return false }
        records = try store.snapshots()
        storeRevision = revision
        presentationRevision &+= 1
        return true
    }

    func presentationChanged() { presentationRevision &+= 1 }
}

private enum FavoritesCoordinatorError: LocalizedError {
    case storeUnavailable
    var errorDescription: String? { "Shared Favorites store is unavailable." }
}
