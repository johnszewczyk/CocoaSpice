import Foundation

enum ArchiveCacheMode: String, CaseIterable, Sendable {
    case enabled
    case disabled
}

/// Persistent limits for archive playback materialization. Scan scratch is
/// intentionally outside this policy: it is disposable work owned by a scan.
struct ArchiveCachePolicy: Sendable, Equatable {
    static let supportedLimits: [Int64] = [2, 4, 8, 16].map { Int64($0) * 1_024 * 1_024 * 1_024 }
    static let defaultLimitBytes: Int64 = 2_048 * 1_024 * 1_024
    static let disposableLimitBytes: Int64 = 2_048 * 1_024 * 1_024
    static let requiredFreeBytes: Int64 = 1_024 * 1_024 * 1_024

    let mode: ArchiveCacheMode
    let maximumBytes: Int64

    static func load(defaults: UserDefaults = .standard) -> ArchiveCachePolicy {
        let mode = ArchiveCacheMode(rawValue: defaults.string(forKey: AppDefaultsKey.archiveCacheMode) ?? "enabled") ?? .enabled
        let requested = Int64(defaults.object(forKey: AppDefaultsKey.archiveCacheLimitBytes) as? Int ?? Int(defaultLimitBytes))
        let maximumBytes = supportedLimits.min(by: { abs($0 - requested) < abs($1 - requested) }) ?? defaultLimitBytes
        return ArchiveCachePolicy(mode: mode, maximumBytes: maximumBytes)
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: AppDefaultsKey.archiveCacheMode)
        defaults.set(Int(maximumBytes), forKey: AppDefaultsKey.archiveCacheLimitBytes)
    }

    var isEnabled: Bool { mode == .enabled }
    var activeLimitBytes: Int64 { isEnabled ? maximumBytes : Self.disposableLimitBytes }

    static func displayLimit(_ bytes: Int64) -> String {
        let gibibyte: Int64 = 1_024 * 1_024 * 1_024
        return "\(max(1, bytes / gibibyte)) GB"
    }
}
