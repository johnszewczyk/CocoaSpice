import Foundation
import Testing
@testable import CocoaSpice

@Test func detachingAttachedRootsPreservesTheirDatabaseIdentity() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-detach-roots-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"))
    try database.addRoot(path: directory.appendingPathComponent("First").path)
    try database.addRoot(path: directory.appendingPathComponent("Second").path)
    let attachedRootIDs = Set(try database.loadRoots().map(\.id))

    try database.detachAttachedRoots()

    #expect(try database.loadRoots().isEmpty)
    try database.addRoot(path: directory.appendingPathComponent("First").path)
    let restoredRoot = try #require(database.loadRoots().first)
    #expect(attachedRootIDs.contains(restoredRoot.id))
}
