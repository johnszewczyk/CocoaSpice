import Foundation

enum SPCMetadataReader {
    enum ReaderError: LocalizedError {
        case notAnSPCFile
        case malformedExtendedTag

        var errorDescription: String? {
            switch self {
            case .notAnSPCFile:
                return "Not an SPC file with readable ID666 metadata."
            case .malformedExtendedTag:
                return "The SPC extended ID666 metadata is malformed."
            }
        }
    }

    private static let headerSize = 0x100
    private static let extendedTagOffset = 0x10200
    private static let headerMagic = Array("SNES-SPC700 Sound File Data".utf8)

    /// Reads SPC metadata without creating a libgme emulator. Returns `nil` when
    /// the file has no readable ID666 or xID6 tag so the generic inspector can
    /// retain compatibility with unusual SPC variants.
    static func read(fileURL: URL) throws -> TrackMetadata? {
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard fileData.count >= headerSize,
              Array(fileData.prefix(headerMagic.count)) == headerMagic else {
            throw ReaderError.notAnSPCFile
        }

        let legacyMetadata = legacyMetadata(in: fileData)
        let extendedTagMetadata: ExtendedMetadata
        do {
            extendedTagMetadata = try extendedMetadata(in: fileData)
        } catch ReaderError.malformedExtendedTag where legacyMetadata.hasTag {
            // Some preserved SPC sets carry a valid legacy ID666 tag followed by
            // a truncated or over-declared xID6 suffix. Keep the independently
            // valid primary tag rather than rejecting the track entirely.
            extendedTagMetadata = ExtendedMetadata()
        }
        guard legacyMetadata.hasTag || extendedTagMetadata.hasTag else { return nil }

        return TrackMetadata(
            game: extendedTagMetadata.game ?? legacyMetadata.game,
            song: extendedTagMetadata.song ?? legacyMetadata.song,
            system: "Super Nintendo",
            author: extendedTagMetadata.author ?? legacyMetadata.author,
            comment: extendedTagMetadata.comment ?? legacyMetadata.comment,
            introLengthMs: extendedTagMetadata.introLengthMs ?? 0,
            loopLengthMs: extendedTagMetadata.loopLengthMs ?? 0,
            playLengthMs: extendedTagMetadata.playLengthMs ?? legacyMetadata.playLengthMs,
            fadeLengthMs: extendedTagMetadata.fadeLengthMs ?? legacyMetadata.fadeLengthMs
        )
    }

    private static func legacyMetadata(in data: Data) -> LegacyMetadata {
        guard data.count >= headerSize, data[0x23] == 0x1A else { return LegacyMetadata() }

        let textDate = data[0x9E..<0xA9]
        let textFade = data[0xAC..<0xB1]
        let binaryLayout = !containsTextDate(textDate)
            && !containsASCIIDigit(textFade)
            && data[0xB0] <= 0x7F
        let artistOffset = binaryLayout ? 0xB0 : 0xB1
        let fadeLengthMs: Int
        if binaryLayout {
            fadeLengthMs = Int(littleEndianUInt32(data, at: 0xAC) ?? 0)
        } else {
            fadeLengthMs = decimal(data[0xAC..<0xB1])
        }

        return LegacyMetadata(
            hasTag: true,
            game: text(data[0x4E..<0x6E]),
            song: text(data[0x2E..<0x4E]),
            author: text(data[artistOffset..<(artistOffset + 32)]),
            comment: text(data[0x7E..<0x9E]),
            playLengthMs: decimal(data[0xA9..<0xAC]) * 1_000,
            fadeLengthMs: fadeLengthMs
        )
    }

    private static func extendedMetadata(in data: Data) throws -> ExtendedMetadata {
        guard data.count >= extendedTagOffset + 8 else { return ExtendedMetadata() }
        guard Array(data[extendedTagOffset..<(extendedTagOffset + 4)]) == Array("xid6".utf8) else {
            return ExtendedMetadata()
        }
        guard let payloadLength = littleEndianUInt32(data, at: extendedTagOffset + 4) else {
            throw ReaderError.malformedExtendedTag
        }

        let payloadStart = extendedTagOffset + 8
        let payloadEnd = payloadStart + Int(payloadLength)
        guard payloadEnd <= data.count else { throw ReaderError.malformedExtendedTag }

        var metadata = ExtendedMetadata(hasTag: true)
        var offset = payloadStart
        while offset < payloadEnd {
            guard offset + 4 <= payloadEnd else { throw ReaderError.malformedExtendedTag }
            let itemID = data[offset]
            let type = data[offset + 1]
            let storedLength = Int(littleEndianUInt16(data, at: offset + 2) ?? 0)
            offset += 4

            let payload: Data.SubSequence
            switch type {
            case 0:
                payload = data[offset..<offset]
            case 1, 4:
                guard offset + storedLength <= payloadEnd else { throw ReaderError.malformedExtendedTag }
                payload = data[offset..<(offset + storedLength)]
                offset += (storedLength + 3) & ~3
                guard offset <= payloadEnd else { throw ReaderError.malformedExtendedTag }
            default:
                throw ReaderError.malformedExtendedTag
            }

            switch (itemID, type) {
            case (0x01, 1): metadata.song = text(payload)
            case (0x02, 1): metadata.game = text(payload)
            case (0x03, 1): metadata.author = text(payload)
            case (0x07, 1): metadata.comment = text(payload)
            case (0x30, 4): metadata.introLengthMs = ticksToMilliseconds(payload)
            case (0x31, 4): metadata.loopLengthMs = ticksToMilliseconds(payload)
            case (0x32, 4): metadata.playLengthMs = ticksToMilliseconds(payload)
            case (0x33, 4): metadata.fadeLengthMs = ticksToMilliseconds(payload)
            default: break
            }
        }
        return metadata
    }

    private static func text(_ bytes: some Collection<UInt8>) -> String {
        let data = Data(bytes.prefix { $0 != 0 })
        let decoded = String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsTextDate(_ bytes: some Collection<UInt8>) -> Bool {
        bytes.allSatisfy { $0 == 0 || $0 == 0x20 || (0x2F...0x39).contains($0) }
            && bytes.contains { (0x2F...0x39).contains($0) }
    }

    private static func containsASCIIDigit(_ bytes: some Collection<UInt8>) -> Bool {
        bytes.allSatisfy { $0 == 0 || $0 == 0x20 || (0x30...0x39).contains($0) }
            && bytes.contains { (0x30...0x39).contains($0) }
    }

    private static func decimal(_ bytes: some Collection<UInt8>) -> Int {
        Int(text(bytes)) ?? 0
    }

    private static func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func ticksToMilliseconds(_ payload: Data.SubSequence) -> Int? {
        guard payload.count == 4 else { return nil }
        let ticks = UInt32(payload[payload.startIndex])
            | (UInt32(payload[payload.index(payload.startIndex, offsetBy: 1)]) << 8)
            | (UInt32(payload[payload.index(payload.startIndex, offsetBy: 2)]) << 16)
            | (UInt32(payload[payload.index(payload.startIndex, offsetBy: 3)]) << 24)
        return Int((Int64(ticks) * 1_000) / 64_000)
    }
}

private struct LegacyMetadata {
    var hasTag = false
    var game = ""
    var song = ""
    var author = ""
    var comment = ""
    var playLengthMs = 0
    var fadeLengthMs = 0
}

private struct ExtendedMetadata {
    var hasTag = false
    var game: String?
    var song: String?
    var author: String?
    var comment: String?
    var introLengthMs: Int?
    var loopLengthMs: Int?
    var playLengthMs: Int?
    var fadeLengthMs: Int?
}
