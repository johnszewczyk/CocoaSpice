import Foundation

/// Reads the `[TAG]` footer shared by PSF-family containers. This avoids
/// opening an emulator or resolving `_lib` dependencies during a library scan;
/// playback continues to materialize the complete dependency set.
enum PSFMetadataReader {
    private static let maximumTagBytes = 1_048_576

    static func read(fileURL: URL) throws -> TrackMetadata? {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: 16), header.count == 16,
              header.prefix(3) == Data("PSF".utf8) else {
            return nil
        }
        let reservedSize = littleEndianUInt32(header, offset: 4)
        let executableSize = littleEndianUInt32(header, offset: 8)
        let tagOffset = 16 + UInt64(reservedSize) + UInt64(executableSize)
        let fileSize = UInt64((try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard tagOffset + 5 <= fileSize else { return metadata(tags: [:], fileURL: fileURL) }

        try handle.seek(toOffset: tagOffset)
        let footerLength = min(UInt64(maximumTagBytes), fileSize - tagOffset)
        guard let footer = try handle.read(upToCount: Int(footerLength)),
              footer.starts(with: Data("[TAG]".utf8)) else {
            return metadata(tags: [:], fileURL: fileURL)
        }
        return metadata(tags: tags(in: footer.dropFirst(5)), fileURL: fileURL)
    }

    private static func littleEndianUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func tags(in footer: Data.SubSequence) -> [String: String] {
        let text = String(decoding: footer, as: UTF8.self)
        return text.split(whereSeparator: \.isNewline).reduce(into: [:]) { tags, line in
            guard let equals = line.firstIndex(of: "=") else { return }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { return }
            // PSF loaders retain the first dependency declaration; all normal
            // user-facing tags are unique, so keeping the first is consistent.
            if tags[key] == nil { tags[key] = value }
        }
    }

    private static func metadata(tags: [String: String], fileURL: URL) -> TrackMetadata {
        let extensionName = fileURL.pathExtension.lowercased()
        return TrackMetadata(
            game: tags["game"] ?? "",
            song: tags["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
            system: systemName(for: extensionName),
            author: tags["artist"] ?? "",
            comment: tags["comment"] ?? "",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: milliseconds(tags["length"]),
            fadeLengthMs: milliseconds(tags["fade"])
        )
    }

    private static func systemName(for extensionName: String) -> String {
        switch extensionName {
        case "psf", "minipsf": return "PlayStation"
        case "psf2", "minipsf2": return "PlayStation 2"
        case "usf", "miniusf": return "Nintendo 64"
        case "2sf", "mini2sf": return "Nintendo DS"
        case "ssf", "minissf": return "Sega Saturn"
        default: return ""
        }
    }

    private static func milliseconds(_ value: String?) -> Int {
        guard let value else { return 0 }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard let secondsPart = parts.last.flatMap({ Double($0) }) else { return 0 }
        let wholeMinutes = parts.dropLast().reversed().enumerated().reduce(0.0) { total, item in
            total + (Double(item.element) ?? 0) * pow(60, Double(item.offset + 1))
        }
        return max(0, Int(((wholeMinutes + secondsPart) * 1_000).rounded()))
    }
}
