import AppKit

enum DatabaseFileSidebarInteraction {
    static let disclosureLeading: CGFloat = 4
    /// The glyph follows the selected font; the user-selected label gap is points.
    static func disclosureGlyphWidth(fontSize: CGFloat) -> CGFloat {
        max(10, ceil(fontSize * 0.9))
    }

    static func disclosureGapWidth(gap: CGFloat) -> CGFloat {
        min(max(gap, 0), 48)
    }

    static func indentationStep(fontSize: CGFloat, gap: CGFloat) -> CGFloat {
        disclosureGlyphWidth(fontSize: fontSize) + disclosureGapWidth(gap: gap)
    }

    static func disclosureOrigin(depth: Int, fontSize: CGFloat, gap: CGFloat) -> CGFloat {
        disclosureLeading + (CGFloat(depth) * indentationStep(fontSize: fontSize, gap: gap))
    }

    static func titleLeading(depth: Int, fontSize: CGFloat, gap: CGFloat) -> CGFloat {
        disclosureOrigin(depth: depth, fontSize: fontSize, gap: gap)
            + indentationStep(fontSize: fontSize, gap: gap)
    }

    /// Folder disclosure is a direct click action. The remainder of the row
    /// remains selectable so Return and double-click can queue its descendants.
    static func allowsFolderDisclosure(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.intersection([.shift, .command, .control]).isEmpty
    }

    static func isDisclosureHit(locationX: CGFloat, depth: Int, fontSize: CGFloat, gap: CGFloat) -> Bool {
        let leading = disclosureOrigin(depth: depth, fontSize: fontSize, gap: gap)
        return locationX >= leading && locationX < leading + disclosureGlyphWidth(fontSize: fontSize)
    }
}
