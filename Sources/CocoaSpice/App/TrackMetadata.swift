import Foundation
import VGMBoyKit

/// Metadata published in the selected catalog. CocoaSpice never decodes a
/// source or asks VGMBoyKit to populate these fields.
struct TrackMetadata: Codable, Equatable, Sendable {
    let game: String
    let song: String
    let system: String
    let author: String
    let comment: String
    let introLengthMs: Int
    let loopLengthMs: Int
    let playLengthMs: Int
    let fadeLengthMs: Int

    var playbackTimingMetadata: PlaybackTimingMetadata {
        PlaybackTimingMetadata(
            playMilliseconds: playLengthMs,
            introMilliseconds: introLengthMs,
            loopMilliseconds: loopLengthMs
        )
    }
}
