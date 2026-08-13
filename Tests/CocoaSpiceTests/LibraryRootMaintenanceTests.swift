import Foundation
import Testing
@testable import CocoaSpice

@Test func configuredLibraryDatabasePathIsExplicitAndStandardized() throws {
    let suiteName = "CocoaSpiceTests.database-path.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("/tmp/Shared Library/../Shared Library/Library.sqlite", forKey: AppDefaultsKey.libraryDatabasePath)

    #expect(try LibraryDatabase.configuredDatabaseURL(defaults: defaults).path == "/tmp/Shared Library/Library.sqlite")
}

@Test func configuredLibraryDatabasePathRejectsRelativeValues() throws {
    let suiteName = "CocoaSpiceTests.database-relative-path.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("Library.sqlite", forKey: AppDefaultsKey.libraryDatabasePath)

    #expect(throws: Error.self) {
        try LibraryDatabase.configuredDatabaseURL(defaults: defaults)
    }
}

@Test func detachingAttachedRootsPreservesTheirDatabaseIdentity() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-detach-roots-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"), accessMode: .readWrite)
    try database.addRoot(path: directory.appendingPathComponent("First").path)
    try database.addRoot(path: directory.appendingPathComponent("Second").path)
    let attachedRootIDs = Set(try database.loadRoots().map(\.id))

    try database.detachAttachedRoots()

    #expect(try database.loadRoots().isEmpty)
    try database.addRoot(path: directory.appendingPathComponent("First").path)
    let restoredRoot = try #require(database.loadRoots().first)
    #expect(attachedRootIDs.contains(restoredRoot.id))
}

@Test func updatingRootEnableStatesPersistsOneBatchOfCheckboxChanges() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-root-enable-states-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try LibraryDatabase(databaseURL: directory.appendingPathComponent("Library.sqlite"), accessMode: .readWrite)
    try database.addRoot(path: directory.appendingPathComponent("First").path)
    try database.addRoot(path: directory.appendingPathComponent("Second").path)
    let roots = try database.loadRoots()
    let first = try #require(roots.first(where: { $0.path.hasSuffix("First") }))
    let second = try #require(roots.first(where: { $0.path.hasSuffix("Second") }))

    try database.setRootEnabledStates([first.id: false, second.id: false])

    #expect(try database.loadRoots().allSatisfy { !$0.isEnabled })
}

@Test func readOnlyLibraryConnectionRejectsMutationsAtSQLiteBoundary() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-read-only-library-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("Library.sqlite")

    let writer = try LibraryDatabase(databaseURL: databaseURL, accessMode: .readWrite)
    try writer.addRoot(path: directory.appendingPathComponent("Music").path)

    let reader = try LibraryDatabase(databaseURL: databaseURL, accessMode: .readOnly)
    #expect(reader.isReadOnly)
    #expect(try reader.loadRoots().count == 1)
    #expect(throws: Error.self) {
        try reader.addRoot(path: directory.appendingPathComponent("Must Not Be Added").path)
    }
    #expect(try reader.loadRoots().count == 1)
}
