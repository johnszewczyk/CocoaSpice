import Foundation
import Testing
@testable import CocoaSpice

private struct CrossAppLibraryIdentityContract: Decodable {
    let contract: String
    let version: Int
    let cases: [CrossAppLibraryIdentityCase]
}

private struct CrossAppLibraryIdentityCase: Decodable {
    struct Metadata: Decodable {
        let game: String
        let system: String
    }

    struct Route: Decodable {
        let pluginID: String
        let formatExtension: String
    }

    struct ExpectedModes: Decodable {
        let collection: CrossAppLibraryIdentity
        let embedded: CrossAppLibraryIdentity
    }

    let id: String
    let sourcePath: String
    let rootPath: String
    let archiveEntry: String?
    let metadata: Metadata
    let route: Route
    let expected: ExpectedModes
}

private struct CrossAppLibraryIdentity: Decodable, Equatable {
    let game: String
    let system: String
}

@Test func matchesCrossAppLibraryIdentityContract() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "cross-app-library-identity-v1",
            withExtension: "json"
        )
    )
    let contract = try JSONDecoder().decode(
        CrossAppLibraryIdentityContract.self,
        from: Data(contentsOf: fixtureURL)
    )

    #expect(contract.contract == "cocoaspice-spcboy-library-identity")
    #expect(contract.version == 1)
    #expect(!contract.cases.isEmpty)

    for fixture in contract.cases {
        let route = ScanRoute(
            pluginID: fixture.route.pluginID,
            formatExtension: fixture.route.formatExtension,
            supportsArchiveMembers: fixture.archiveEntry != nil,
            supportsMultiTrack: false
        )
        let game = LibraryConsoleResolver.browserGame(
            metadataGame: fixture.metadata.game,
            sourcePath: fixture.sourcePath,
            archiveEntry: fixture.archiveEntry
        )
        let collection = CrossAppLibraryIdentity(
            game: game,
            system: LibraryConsoleResolver.browserSystem(
                metadataSystem: fixture.metadata.system,
                route: route,
                sourcePath: fixture.sourcePath,
                rootPath: fixture.rootPath
            )
        )
        let embedded = CrossAppLibraryIdentity(
            game: game,
            system: LibraryConsoleResolver.browserSystem(
                metadataSystem: fixture.metadata.system,
                route: route,
                sourcePath: fixture.sourcePath,
                rootPath: fixture.rootPath,
                preferEmbeddedMetadata: true
            )
        )

        #expect(collection == fixture.expected.collection, "\(fixture.id) collection mode")
        #expect(embedded == fixture.expected.embedded, "\(fixture.id) embedded mode")
    }
}
