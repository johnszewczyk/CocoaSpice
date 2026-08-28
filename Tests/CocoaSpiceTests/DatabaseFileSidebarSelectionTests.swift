import Testing
@testable import CocoaSpice

@MainActor
@Test func fileSidebarSelectedFolderToggleFoldsAnOpenFolder() {
    let sidebar = DatabaseFileSidebarState()
    let folderID = DatabaseFileSidebarTree.folderID(rootID: 7, path: "/music/Library/Console")

    sidebar.expandFolder(folderID)
    sidebar.expandFolder(folderID)

    #expect(sidebar.expandedFolderIDs == [folderID])
    sidebar.toggleFolder(folderID)
    #expect(!sidebar.expandedFolderIDs.contains(folderID))
    sidebar.toggleFolder(folderID)
    #expect(sidebar.expandedFolderIDs == [folderID])
}

@Test func multiTrackFilesPopulatePlaylistOnSelection() {
    let sndh = DatabaseFileItem(
        rootID: 1,
        rootPath: "/audio/AtariST",
        folderPath: "/audio/AtariST",
        path: "/audio/AtariST/Zone_Warrior.sndh",
        isArchive: false,
        trackCount: 4
    )
    let singleTrack = DatabaseFileItem(
        rootID: 1,
        rootPath: "/audio/AtariST",
        folderPath: "/audio/AtariST",
        path: "/audio/AtariST/one-track.sndh",
        isArchive: false,
        trackCount: 1
    )
    let archive = DatabaseFileItem(
        rootID: 1,
        rootPath: "/audio/AtariST",
        folderPath: "/audio/AtariST",
        path: "/audio/AtariST/collection.7z",
        isArchive: true,
        trackCount: 1
    )

    #expect(DatabaseFileSidebarInteraction.shouldPopulatePlaylistOnSelection(sndh))
    #expect(!DatabaseFileSidebarInteraction.shouldPopulatePlaylistOnSelection(singleTrack))
    #expect(DatabaseFileSidebarInteraction.shouldPopulatePlaylistOnSelection(archive))
}
