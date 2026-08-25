import ArchiveCacheCore
import Foundation

/// CocoaSpice's preference-key adapter for the shared archive-cache policy.
extension ArchiveCachePolicy {
    static func load(defaults: UserDefaults = .standard) -> ArchiveCachePolicy {
        load(
            defaults: defaults,
            keys: ArchiveCachePreferenceKeys(
                modeKey: AppDefaultsKey.archiveCacheMode,
                limitKey: AppDefaultsKey.archiveCacheLimitBytes
            )
        )
    }

    func save(defaults: UserDefaults = .standard) {
        save(
            defaults: defaults,
            keys: ArchiveCachePreferenceKeys(
                modeKey: AppDefaultsKey.archiveCacheMode,
                limitKey: AppDefaultsKey.archiveCacheLimitBytes
            )
        )
    }
}
