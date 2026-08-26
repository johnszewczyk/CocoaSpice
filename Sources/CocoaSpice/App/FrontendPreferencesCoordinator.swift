import FrontendPreferencesCore

extension FrontendPreferencesKeySet {
    static let cocoaSpice = FrontendPreferencesKeySet(
        autoResizeEnabledKey: AppDefaultsKey.autoResizeAnimationEnabled,
        selectionEnabledKey: AppDefaultsKey.selectionAnimationEnabled,
        autoResizeMillisecondsKey: AppDefaultsKey.autoResizeAnimationMilliseconds,
        selectionMillisecondsKey: AppDefaultsKey.selectionAnimationMilliseconds,
        columnAutoSizeKey: AppDefaultsKey.columnAutoSize,
        mainWindowAlwaysOnTopKey: AppDefaultsKey.mainWindowAlwaysOnTop,
        settingsWindowAlwaysOnTopKey: AppDefaultsKey.settingsWindowAlwaysOnTop
    )
}
