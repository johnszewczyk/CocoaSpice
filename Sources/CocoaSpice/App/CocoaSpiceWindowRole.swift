import AppKit
import FrontendPreferencesCore

extension NSUserInterfaceItemIdentifier {
    static func cocoaSpiceWindow(_ role: FrontendWindowRole) -> Self {
        Self("com.cocoaspice.window.\(role.rawValue)")
    }
}

extension NSWindow {
    var cocoaSpiceRole: FrontendWindowRole? {
        get {
            FrontendWindowRole.allCases.first { identifier == .cocoaSpiceWindow($0) }
        }
        set {
            identifier = newValue.map(NSUserInterfaceItemIdentifier.cocoaSpiceWindow)
        }
    }
}
