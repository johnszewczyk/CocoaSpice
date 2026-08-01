import Foundation
import Testing
@testable import CocoaSpice

@Test func highlyTheoreticalDecodesRealSaturnPCMAndSSFLibraries() throws {
    let fixtureRoot = URL(fileURLWithPath: "/private/tmp/cocoaspice-ssf-fixture", isDirectory: true)
    guard FileManager.default.fileExists(atPath: fixtureRoot.path) else { return }

    for filename in ["BGM_000.ssf", "BGM_069_00_00.ssf"] {
        let fileURL = fixtureRoot.appendingPathComponent(filename)
        let decoder = try HighlyTheoreticalDecoder(track: TrackItem(url: fileURL), sampleRate: 44_100)
        let metadata = try decoder.metadata()
        var emittedPCM = false
        for _ in 0..<16 {
            let chunk = try decoder.decode(frameCount: 4_096)
            emittedPCM = emittedPCM || chunk.left.contains(where: { abs($0) > 0.0001 })
                || chunk.right.contains(where: { abs($0) > 0.0001 })
            if emittedPCM { break }
        }

        #expect(metadata.system == "Sega Saturn")
        #expect(decoder.playedFrames > 0)
        #expect(emittedPCM, "Expected non-silent PCM for \(filename).")
    }
}
