import Foundation
import FrontendPreferencesCore
import Observation

@MainActor @Observable
final class FrontendPreferencesCoordinator {
    private(set) var value: FrontendInterfacePreferences
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = FrontendInterfacePreferences(
            animations: FrontendAnimationTimings(
                autoResizeMilliseconds: defaults.object(forKey: AppDefaultsKey.autoResizeAnimationMilliseconds)
                    .flatMap { ($0 as? NSNumber)?.intValue } ?? FrontendAnimationTimings.defaultDurationMilliseconds,
                selectionMilliseconds: defaults.object(forKey: AppDefaultsKey.selectionAnimationMilliseconds)
                    .flatMap { ($0 as? NSNumber)?.intValue } ?? FrontendAnimationTimings.defaultDurationMilliseconds
            ),
            windows: FrontendWindowPreferences(
                mainAlwaysOnTop: defaults.bool(forKey: AppDefaultsKey.mainWindowAlwaysOnTop),
                settingsAlwaysOnTop: defaults.bool(forKey: AppDefaultsKey.settingsWindowAlwaysOnTop)
            )
        )
    }

    func setAutoResizeMilliseconds(_ milliseconds: Int) {
        value.animations.autoResizeMilliseconds = FrontendAnimationTimings.clamp(milliseconds)
        defaults.set(value.animations.autoResizeMilliseconds, forKey: AppDefaultsKey.autoResizeAnimationMilliseconds)
    }

    func setSelectionMilliseconds(_ milliseconds: Int) {
        value.animations.selectionMilliseconds = FrontendAnimationTimings.clamp(milliseconds)
        defaults.set(value.animations.selectionMilliseconds, forKey: AppDefaultsKey.selectionAnimationMilliseconds)
    }

    func setAlwaysOnTop(_ enabled: Bool, role: FrontendWindowRole) {
        switch role {
        case .main:
            value.windows.mainAlwaysOnTop = enabled
            defaults.set(enabled, forKey: AppDefaultsKey.mainWindowAlwaysOnTop)
        case .settings:
            value.windows.settingsAlwaysOnTop = enabled
            defaults.set(enabled, forKey: AppDefaultsKey.settingsWindowAlwaysOnTop)
        case .about:
            break
        }
    }
}
