import Foundation

/// Small read-only admission checks retained by the playlist frontend. These
/// decide whether a dropped file is a playable source; they do not inspect or
/// write ScanSong's catalog.
enum WwiseBankDetector {
    static func isEventBank(_ fileURL: URL) -> Bool {
        guard fileURL.pathExtension.lowercased() == "bnk",
              let header = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]).prefix(4) else {
            return false
        }
        return header == Data("BKHD".utf8)
    }
}

enum HeaderlessSS2Detector {
    static func isUnsupportedResource(_ fileURL: URL) -> Bool {
        guard fileURL.pathExtension.lowercased() == "ss2",
              let header = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]).prefix(4) else {
            return false
        }
        return header != Data("SShd".utf8)
    }
}
