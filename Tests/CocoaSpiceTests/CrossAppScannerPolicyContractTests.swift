import Foundation
import Testing
@testable import CocoaSpice

private struct CrossAppScannerPolicyContract: Decodable {
    struct Case: Decodable {
        let `extension`: String
        let structurePolicy: String
        let metadataPolicy: String
    }

    let contract: String
    let version: Int
    let cases: [Case]
}

@Test func matchesCrossAppScannerPolicyContract() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "cross-app-scanner-policy-v1", withExtension: "json")
    )
    let contract = try JSONDecoder().decode(
        CrossAppScannerPolicyContract.self,
        from: Data(contentsOf: fixtureURL)
    )
    #expect(contract.contract == "cocoaspice-spcboy-scanner-policy")
    #expect(contract.version == 1)
    for item in contract.cases {
        let route = try #require(ScanCoreHandlers.registry.route(for: item.extension))
        #expect(route.structurePolicy.rawValue == item.structurePolicy)
        #expect(route.metadataPolicy.rawValue == item.metadataPolicy)
    }
}
