import Testing
@testable import CocoaSpice

@MainActor
@Test func fileSidebarSelectionExpandsWithoutCollapsingAnOpenFolder() {
    let sidebar = DatabaseFileSidebarState()
    let folderID = DatabaseFileSidebarTree.folderID(rootID: 7, path: "/music/Library/Console")

    sidebar.expandFolder(folderID)
    sidebar.expandFolder(folderID)

    #expect(sidebar.expandedFolderIDs == [folderID])
    sidebar.toggleFolder(folderID)
    #expect(!sidebar.expandedFolderIDs.contains(folderID))
}
