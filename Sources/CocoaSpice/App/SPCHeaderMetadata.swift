import Foundation

enum SPCHeaderMetadata {
    static func read(from fileURL: URL) -> TrackMetadata? {
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
            return nil
        }
        return parse(data)
    }

    private static func parse(_ data: Data) -> TrackMetadata? {
        let signature = Data("SNES-SPC700 Sound File Data v0.30".utf8)
        guard data.count >= 0x8E,
              data.prefix(signature.count) == signature else {
            return nil
        }

        return TrackMetadata(
            game: text(in: data, offset: 0x4E, length: 32),
            song: text(in: data, offset: 0x2E, length: 32),
            system: "Super Nintendo",
            author: text(in: data, offset: 0x6E, length: 32),
            comment: "",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: 0,
            fadeLengthMs: 0
        )
    }

    private static func text(in data: Data, offset: Int, length: Int) -> String {
        let bytes = data[offset..<(offset + length)]
        return String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
