import Foundation
import Testing
@testable import CocoaSpice

private struct CrossAppScannerLifecycleContract: Decodable {
    let contract: String
    let version: Int
    let phases: [String]
}

@Test func matchesCrossAppScannerLifecycleContract() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "cross-app-scanner-lifecycle-v1",
            withExtension: "json"
        )
    )
    let contract = try JSONDecoder().decode(
        CrossAppScannerLifecycleContract.self,
        from: Data(contentsOf: fixtureURL)
    )

    #expect(contract.contract == "cocoaspice-spcboy-scanner-lifecycle")
    #expect(contract.version == 1)
    #expect(ScanLifecyclePhase.allCases.map(\.rawValue) == contract.phases)
}
