import Foundation

/// Metadata already published in the catalog, or supplied transiently by the
/// playback core. CocoaSpice never decodes a source merely to populate it.
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
}
