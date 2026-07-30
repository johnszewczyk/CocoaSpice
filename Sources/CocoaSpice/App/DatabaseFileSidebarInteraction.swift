import AppKit

enum DatabaseFileSidebarInteraction {
    /// Folder disclosure is a direct click action, never part of a range or
    /// additive row selection.
    static func allowsFolderDisclosure(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.intersection([.shift, .command, .control]).isEmpty
    }
}
