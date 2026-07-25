import Foundation

/// The scanner-facing contract for a playback plugin. This deliberately uses
/// stable string identifiers so future plugins do not need to depend on the
/// current decoder implementation or on CocoaSpice's playback types.
struct ScanPluginDescriptor: Hashable, Sendable {
    let pluginID: String
    let displayName: String
    let supportedExtensions: Set<String>
    let supportsArchiveMembers: Bool
    let supportsMultiTrack: Bool
    let priority: Int

    init(
        pluginID: String,
        displayName: String,
        supportedExtensions: Set<String>,
        supportsArchiveMembers: Bool = true,
        supportsMultiTrack: Bool = false,
        priority: Int = 0
    ) {
        self.pluginID = pluginID
        self.displayName = displayName
        self.supportedExtensions = Set(supportedExtensions.map { Self.normalize($0) })
        self.supportsArchiveMembers = supportsArchiveMembers
        self.supportsMultiTrack = supportsMultiTrack
        self.priority = priority
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
    }
}

struct ScanRoute: Hashable, Sendable {
    let pluginID: String
    let formatExtension: String
    let supportsArchiveMembers: Bool
    let supportsMultiTrack: Bool
}

struct ScanPluginRegistry: Sendable {
    private let descriptors: [ScanPluginDescriptor]

    init(descriptors: [ScanPluginDescriptor]) {
        self.descriptors = descriptors.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.pluginID < $1.pluginID
        }
    }

    var supportedExtensions: Set<String> {
        Set(descriptors.flatMap(\.supportedExtensions))
    }

    func route(for pathExtension: String, archiveMember: Bool = false) -> ScanRoute? {
        let normalized = pathExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        guard let descriptor = descriptors.first(where: {
            $0.supportedExtensions.contains(normalized)
                && (!archiveMember || $0.supportsArchiveMembers)
        }) else {
            return nil
        }
        return ScanRoute(
            pluginID: descriptor.pluginID,
            formatExtension: normalized,
            supportsArchiveMembers: descriptor.supportsArchiveMembers,
            supportsMultiTrack: descriptor.supportsMultiTrack
        )
    }
}

enum ScanMode: String, CaseIterable, Sendable {
    case incremental
    case newScan
}

enum ScanItemState: String, Sendable {
    case discovered
    case queued
    case scanning
    case successful
    case failed
    case unsupported
    case cancelled
}

struct ScanItemIdentity: Hashable, Sendable {
    let rootID: Int64
    let path: String
    let archiveEntry: String?
}

struct ScanFingerprint: Hashable, Sendable {
    let fileSize: Int64
    let modifiedAt: Date
    /// Tool-reported archive details for a supported archive. It is nil for
    /// ordinary files and legacy inventory rows until their next scan.
    let contentSignature: String?

    init(fileSize: Int64, modifiedAt: Date, contentSignature: String? = nil) {
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.contentSignature = contentSignature
    }

    func matches(_ current: ScanFingerprint) -> Bool {
        if fileSize == current.fileSize, modifiedAt == current.modifiedAt {
            return true
        }
        return contentSignature != nil && contentSignature == current.contentSignature
    }
}

struct ScanInventoryItem: Sendable {
    let identity: ScanItemIdentity
    let fingerprint: ScanFingerprint
    let state: ScanItemState
    let route: ScanRoute?
}

enum ScanSelection {
    static func includes(
        _ item: ScanInventoryItem,
        mode: ScanMode,
        currentFingerprint: ScanFingerprint
    ) -> Bool {
        switch mode {
        case .newScan:
            return true
        case .incremental:
            return item.state != .successful || !item.fingerprint.matches(currentFingerprint)
        }
    }
}
