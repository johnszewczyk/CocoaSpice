import CLibVGM
import Foundation

enum VGMMetadataReader {
    /// Reads GD3 metadata from VGM/VGZ without creating a libVGM player.
    /// Untagged and unusual files return nil so the full inspector remains the
    /// compatibility path.
    static func read(fileURL: URL) -> TrackMetadata? {
        let extensionName = fileURL.pathExtension.lowercased()
        guard extensionName == "vgm" || extensionName == "vgz" else { return nil }

        var rawMetadata = libvgm_metadata_t()
        defer { libvgm_metadata_clear(&rawMetadata) }
        let status = fileURL.path.withCString { path in
            libvgm_read_vgm_metadata_fast(path, &rawMetadata)
        }
        guard status == 0 else { return nil }
        return LibVGMDecoder.trackMetadata(from: rawMetadata)
    }
}
