import AppKit

enum DatabaseFileSidebarInteraction {
    static let disclosureLeading: CGFloat = 4
    /// The glyph follows the selected font; the user-selected label gap is points.
    static func disclosureGlyphWidth(fontSize: CGFloat) -> CGFloat {
        max(10, ceil(fontSize * 0.9))
    }

    static func disclosureGapWidth(gap: CGFloat) -> CGFloat {
        min(max(gap, 0), 16)
    }

    static func indentationStep(fontSize: CGFloat, gap: CGFloat) -> CGFloat {
        disclosureGlyphWidth(fontSize: fontSize) + disclosureGapWidth(gap: gap)
    }

    static func childIndentWidth(_ indent: CGFloat) -> CGFloat {
        min(max(indent, 0), 32)
    }

    static func disclosureOrigin(depth: Int, fontSize: CGFloat, gap: CGFloat, childIndent: CGFloat) -> CGFloat {
        disclosureLeading
            + (CGFloat(depth) * indentationStep(fontSize: fontSize, gap: gap))
            + (CGFloat(depth) * childIndentWidth(childIndent))
    }

    static func titleLeading(depth: Int, fontSize: CGFloat, gap: CGFloat, childIndent: CGFloat) -> CGFloat {
        disclosureOrigin(depth: depth, fontSize: fontSize, gap: gap, childIndent: childIndent)
            + indentationStep(fontSize: fontSize, gap: gap)
    }

    /// Folder disclosure is a direct click action. The remainder of the row
    /// remains selectable so Return and double-click can queue its descendants.
    static func allowsFolderDisclosure(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.intersection([.shift, .command, .control]).isEmpty
    }

    /// Selecting a container or a catalog source with multiple tracks should
    /// populate the playlist without requiring a second activation gesture.
    /// Single-track files remain selection-only so browsing does not silently
    /// replace a queue for ordinary files.
    static func shouldPopulatePlaylistOnSelection(_ item: DatabaseFileItem) -> Bool {
        item.isArchive || item.trackCount > 1
    }

    static func isDisclosureHit(locationX: CGFloat, depth: Int, fontSize: CGFloat, gap: CGFloat, childIndent: CGFloat) -> Bool {
        let leading = disclosureOrigin(depth: depth, fontSize: fontSize, gap: gap, childIndent: childIndent)
        return locationX >= leading && locationX < leading + disclosureGlyphWidth(fontSize: fontSize)
    }
}
