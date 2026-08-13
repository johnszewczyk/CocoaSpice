import Foundation
import Testing
@testable import CocoaSpice

private struct CrossAppPlaylistActivationContract: Decodable {
    let contract: String
    let version: Int
    let cases: [CrossAppPlaylistActivationCase]
}

private struct CrossAppPlaylistActivationCase: Decodable {
    let id: String
    let sourcePath: String
    let archiveEntry: String?
    let trackCount: Int
    let metadataBefore: [String]
    let metadataAfter: [String]
    let expectedTrackIDs: [String]
}

@Test func matchesCrossAppPlaylistActivationContract() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "cross-app-playlist-activation-v1",
            withExtension: "json"
        )
    )
    let contract = try JSONDecoder().decode(
        CrossAppPlaylistActivationContract.self,
        from: Data(contentsOf: fixtureURL)
    )

    #expect(contract.contract == "cocoaspice-spcboy-playlist-activation")
    #expect(contract.version == 1)
    #expect(!contract.cases.isEmpty)

    for fixture in contract.cases {
        let sourceURL = URL(fileURLWithPath: fixture.sourcePath)
        let tracks: [TrackItem]
        if let archiveEntry = fixture.archiveEntry {
            tracks = TrackItem.expanded(
                archiveURL: sourceURL,
                entryPath: archiveEntry,
                trackCount: fixture.trackCount
            )
        } else {
            tracks = TrackItem.expanded(url: sourceURL, trackCount: fixture.trackCount)
        }

        #expect(tracks.map(\.trackIndex) == Array(0..<fixture.trackCount), "\(fixture.id)")
        #expect(tracks.map(\.trackCount) == Array(repeating: fixture.trackCount, count: fixture.trackCount), "\(fixture.id)")
        #expect(tracks.map(\.id) == fixture.expectedTrackIDs, "\(fixture.id)")

        var titlesByTrackID = Dictionary(
            uniqueKeysWithValues: zip(tracks.map(\.id), fixture.metadataBefore)
        )
        for (track, title) in zip(tracks, fixture.metadataAfter) {
            titlesByTrackID[track.id] = title
        }
        #expect(tracks.compactMap { titlesByTrackID[$0.id] } == fixture.metadataAfter, "\(fixture.id)")
        #expect(tracks.map(\.id) == fixture.expectedTrackIDs, "\(fixture.id) metadata update changed identity")
    }
}
