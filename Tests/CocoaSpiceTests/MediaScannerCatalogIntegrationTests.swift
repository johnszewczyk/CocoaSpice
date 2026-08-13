import Foundation
import MediaScannerKit
import Testing
@testable import CocoaSpice

@Test func cocoaSpiceReadsCatalogPublishedByMediaScanner() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocoaspice-mediascanner-integration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("Audio", isDirectory: true)
    let game = root
        .appendingPathComponent("Sony PlayStation 2", isDirectory: true)
        .appendingPathComponent("Castlevania", isDirectory: true)
    try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: game.appendingPathComponent("Prologue.wav"))
    let databaseURL = directory.appendingPathComponent("Library.sqlite")

    let scan = try await CatalogScanner(databaseURL: databaseURL).scan(rootURL: root, mode: .newScan)
    #expect(scan.trackCount == 1)
    #expect(scan.failures.isEmpty)

    let database = try LibraryDatabase(databaseURL: databaseURL, accessMode: .readOnly)
    #expect(database.isReadOnly)
    let content = try LibraryDatabase.loadSidebarContent(databaseURL: databaseURL)
    #expect(content.gameItems.count == 1)
    #expect(content.gameItems[0].name == "Castlevania")
    #expect(content.gameItems[0].systemName == "Sony PlayStation 2")
    #expect(content.fileItems.count == 1)

    let playlist = try database.tracksAndMetadataForGames([content.gameItems[0]])
    #expect(playlist.tracks.count == 1)
    #expect(playlist.tracks[0].filename == "Prologue.wav")
    #expect(playlist.tracks[0].url.path == game.appendingPathComponent("Prologue.wav").path)
}
