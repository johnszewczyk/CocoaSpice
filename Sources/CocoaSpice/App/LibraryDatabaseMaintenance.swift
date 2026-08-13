import Foundation

/// Database-only library maintenance work that is safe to run on a short-lived
/// SQLite connection away from the main actor.
struct LibraryDatabaseMaintenanceSummary: Sendable, Equatable {
    let deadLinkCount: Int
    let indexedTrackCount: Int
    let unlinkedTrackCount: Int

    var deadLinkSummaryText: String {
        deadLinkCount == 1 ? "1 unlinked source retained" : "\(deadLinkCount) unlinked sources retained"
    }
}

enum LibraryDatabaseMaintenance {
    static func summary(databaseURL: URL) throws -> LibraryDatabaseMaintenanceSummary {
        let database = try LibraryDatabase(databaseURL: databaseURL, accessMode: .readOnly)
        return LibraryDatabaseMaintenanceSummary(
            deadLinkCount: try database.deadSourceCount(),
            indexedTrackCount: try database.trackCount(),
            unlinkedTrackCount: try database.deadTrackCount()
        )
    }

    static func clearDeadLinks(databaseURL: URL) throws -> Int {
        let database = try LibraryDatabase(databaseURL: databaseURL, accessMode: .readOnly)
        return try database.deleteDeadSources()
    }
}
