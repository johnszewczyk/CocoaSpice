import Foundation
import Testing
@testable import CocoaSpice

private struct CrossAppSidebarSearchContract: Decodable {
    let contract: String
    let version: Int
    let cases: [CrossAppSidebarSearchCase]
}

private struct CrossAppSidebarSearchCase: Decodable {
    struct Step: Decodable {
        let setMode: String?
        let setQuery: String?
        let expected: Expected
    }

    struct Expected: Decodable, Equatable {
        let storedMode: String
        let query: String
        let view: String
        let contentMode: String
        let resultSource: String
        let isTemporary: Bool
    }

    let id: String
    let initialMode: String
    let steps: [Step]
}

@Test func matchesCrossAppSidebarSearchViewContract() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "cross-app-sidebar-search-view-v1",
            withExtension: "json"
        )
    )
    let contract = try JSONDecoder().decode(
        CrossAppSidebarSearchContract.self,
        from: Data(contentsOf: fixtureURL)
    )

    #expect(contract.contract == "cocoaspice-spcboy-sidebar-search-view")
    #expect(contract.version == 1)
    #expect(!contract.cases.isEmpty)

    for fixture in contract.cases {
        var storedMode = try sidebarMode(fixture.initialMode)
        var query = ""
        for step in fixture.steps {
            if let setMode = step.setMode { storedMode = try sidebarMode(setMode) }
            if let setQuery = step.setQuery { query = setQuery }
            let state = PlayerViewModel.sidebarViewResolution(
                storedMode: storedMode,
                searchText: query
            )
            let actual = CrossAppSidebarSearchCase.Expected(
                storedMode: state.storedMode.rawValue,
                query: state.query,
                view: state.view.rawValue,
                contentMode: state.contentMode.rawValue,
                resultSource: state.resultSource,
                isTemporary: state.isTemporary
            )
            #expect(actual == step.expected, "\(fixture.id)")
        }
    }
}

private func sidebarMode(_ value: String) throws -> SidebarBrowserMode {
    switch value {
    case "folders": .files
    case "database": .games
    default:
        throw NSError(
            domain: "CrossAppSidebarSearchContract",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown sidebar mode: \(value)"]
        )
    }
}
