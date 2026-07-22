import Foundation
import Testing
@testable import CocoaSpice

@Test func spcMetadataReaderReadsLegacyID666WithoutLibGME() throws {
    let fileURL = try writeSPCFixture { bytes in
        bytes[0x23] = 0x1A
        writeASCII("Song Title", into: &bytes, at: 0x2E, length: 32)
        writeASCII("Game Title", into: &bytes, at: 0x4E, length: 32)
        writeASCII("Composer", into: &bytes, at: 0xB1, length: 32)
        writeASCII("A comment", into: &bytes, at: 0x7E, length: 32)
        writeASCII("150", into: &bytes, at: 0xA9, length: 3)
        writeASCII("5000", into: &bytes, at: 0xAC, length: 5)
    }
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let metadata = try #require(try SPCMetadataReader.read(fileURL: fileURL))

    #expect(metadata.song == "Song Title")
    #expect(metadata.game == "Game Title")
    #expect(metadata.author == "Composer")
    #expect(metadata.comment == "A comment")
    #expect(metadata.system == "Super Nintendo")
    #expect(metadata.playLengthMs == 150_000)
    #expect(metadata.fadeLengthMs == 5_000)
}

@Test func spcMetadataReaderPrefersExtendedID666PlaybackMetadata() throws {
    let fileURL = try writeSPCFixture { bytes in
        bytes[0x23] = 0x1A
        writeASCII("Legacy Song", into: &bytes, at: 0x2E, length: 32)
        writeASCII("60", into: &bytes, at: 0xA9, length: 3)
        appendExtendedID666(
            to: &bytes,
            strings: [
                (0x01, "Extended Song"),
                (0x02, "Extended Game"),
                (0x03, "Extended Composer")
            ],
            ticks: [
                (0x30, 64_000),
                (0x31, 128_000),
                (0x32, 192_000),
                (0x33, 32_000)
            ]
        )
    }
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let metadata = try #require(try SPCMetadataReader.read(fileURL: fileURL))

    #expect(metadata.song == "Extended Song")
    #expect(metadata.game == "Extended Game")
    #expect(metadata.author == "Extended Composer")
    #expect(metadata.introLengthMs == 1_000)
    #expect(metadata.loopLengthMs == 2_000)
    #expect(metadata.playLengthMs == 3_000)
    #expect(metadata.fadeLengthMs == 500)
}

@Test func spcMetadataReaderReadsBinaryID666Layout() throws {
    let fileURL = try writeSPCFixture { bytes in
        bytes[0x23] = 0x1A
        writeASCII("Binary Song", into: &bytes, at: 0x2E, length: 32)
        writeASCII("Binary Game", into: &bytes, at: 0x4E, length: 32)
        writeASCII("Binary Composer", into: &bytes, at: 0xB0, length: 32)
        writeUInt32(2_500, into: &bytes, at: 0xAC)
        writeASCII("123", into: &bytes, at: 0xA9, length: 3)
    }
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let metadata = try #require(try SPCMetadataReader.read(fileURL: fileURL))

    #expect(metadata.song == "Binary Song")
    #expect(metadata.game == "Binary Game")
    #expect(metadata.author == "Binary Composer")
    #expect(metadata.playLengthMs == 123_000)
    #expect(metadata.fadeLengthMs == 2_500)
}

@Test func spcMetadataReaderKeepsLegacyMetadataWhenExtendedID666IsMalformed() throws {
    let fileURL = try writeSPCFixture { bytes in
        bytes[0x23] = 0x1A
        writeASCII("Recovered Song", into: &bytes, at: 0x2E, length: 32)
        writeASCII("Recovered Game", into: &bytes, at: 0x4E, length: 32)
        writeASCII("Recovered Author", into: &bytes, at: 0xB1, length: 32)
        writeASCII("120", into: &bytes, at: 0xA9, length: 3)
        writeASCII("1000", into: &bytes, at: 0xAC, length: 5)

        // The declared xID6 payload runs past EOF. The legacy tag remains
        // complete and must still make this a successful metadata scan.
        bytes += Array("xid6".utf8)
        bytes += [8, 0, 0, 0]
        bytes += [0x01, 0x01, 4, 0]
    }
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let metadata = try #require(try SPCMetadataReader.read(fileURL: fileURL))

    #expect(metadata.song == "Recovered Song")
    #expect(metadata.game == "Recovered Game")
    #expect(metadata.author == "Recovered Author")
    #expect(metadata.playLengthMs == 120_000)
}

private func writeSPCFixture(
    configure: (inout [UInt8]) -> Void
) throws -> URL {
    var bytes = [UInt8](repeating: 0, count: 0x10200)
    writeASCII("SNES-SPC700 Sound File Data v0.30", into: &bytes, at: 0, length: 33)
    configure(&bytes)

    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("spc")
    try Data(bytes).write(to: fileURL)
    return fileURL
}

private func writeASCII(_ value: String, into bytes: inout [UInt8], at offset: Int, length: Int) {
    let encoded = Array(value.utf8.prefix(length))
    bytes.replaceSubrange(offset..<(offset + encoded.count), with: encoded)
}

private func writeUInt32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
    bytes.replaceSubrange(offset..<(offset + 4), with: [
        UInt8(value & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 24) & 0xFF)
    ])
}

private func appendExtendedID666(
    to bytes: inout [UInt8],
    strings: [(UInt8, String)],
    ticks: [(UInt8, UInt32)]
) {
    var payload: [UInt8] = []
    for (id, value) in strings {
        let encoded = Array(value.utf8) + [0]
        payload += [id, 1, UInt8(encoded.count & 0xFF), UInt8(encoded.count >> 8)]
        payload += encoded
        payload += Array(repeating: 0, count: (4 - (encoded.count % 4)) % 4)
    }
    for (id, value) in ticks {
        payload += [id, 4, 4, 0]
        payload += [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }

    bytes += Array("xid6".utf8)
    let payloadLength = UInt32(payload.count)
    bytes += [
        UInt8(payloadLength & 0xFF),
        UInt8((payloadLength >> 8) & 0xFF),
        UInt8((payloadLength >> 16) & 0xFF),
        UInt8((payloadLength >> 24) & 0xFF)
    ]
    bytes += payload
}
