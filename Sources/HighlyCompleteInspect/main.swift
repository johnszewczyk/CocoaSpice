import CHighlyComplete
import Foundation

private struct Inspection: Encodable {
    let title: String
    let game: String
    let system: String
    let artist: String
    let comment: String
    let introLengthMs: Int
    let loopLengthMs: Int
    let playLengthMs: Int
    let fadeLengthMs: Int
    let trackCount: Int
}

private func string(_ value: UnsafeMutablePointer<CChar>?) -> String {
    guard let value else { return "" }
    return String(cString: value)
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("Usage: highly-complete-inspect /path/to/file.gsf")
}

let path = CommandLine.arguments[1]
var errorMessage: UnsafeMutablePointer<CChar>?
guard let player = highlycomplete_player_create(path, 44_100, 0, &errorMessage) else {
    defer { highlycomplete_error_message_free(errorMessage) }
    fail(string(errorMessage).isEmpty ? "Highly Complete could not open the file." : string(errorMessage))
}
defer { highlycomplete_player_destroy(player) }

var metadata = highlycomplete_metadata_t()
defer { highlycomplete_metadata_clear(&metadata) }
guard highlycomplete_player_read_metadata(player, &metadata, &errorMessage) == 0 else {
    defer { highlycomplete_error_message_free(errorMessage) }
    fail(string(errorMessage).isEmpty ? "Highly Complete could not read the file metadata." : string(errorMessage))
}

private let output = Inspection(
    title: string(metadata.title),
    game: string(metadata.game),
    system: string(metadata.system),
    artist: string(metadata.artist),
    comment: string(metadata.comment),
    introLengthMs: Int(metadata.intro_length_ms),
    loopLengthMs: Int(metadata.loop_length_ms),
    playLengthMs: Int(metadata.play_length_ms),
    fadeLengthMs: Int(metadata.fade_length_ms),
    trackCount: max(1, Int(metadata.track_count))
)

do {
    FileHandle.standardOutput.write(try JSONEncoder().encode(output))
} catch {
    fail("Could not serialize Highly Complete metadata: \(error.localizedDescription)")
}
