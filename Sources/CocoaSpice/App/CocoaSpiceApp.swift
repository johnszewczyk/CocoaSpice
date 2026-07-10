import SwiftUI

@main
struct CocoaSpiceApp: App {
    @State private var model = PlayerViewModel()

    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .onOpenURL { url in
                    model.openPlaylistM3U(at: url)
                }
                .onDisappear {
                    model.saveSessionStateNow()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.saveSessionStateNow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
        .commands {
            CocoaSpiceCommands(model: model)
        }

        Window("Options", id: "options") {
            OptionsView(model: model)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)
    }
}

private struct CocoaSpiceCommands: Commands {
    @Bindable var model: PlayerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Playlist...") {
                model.loadPlaylistM3U()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Save Playlist...") {
                model.savePlaylistM3U()
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Button("Cut Tracks") {
                model.cutSelectedTracks()
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(!model.canCutSelectedTracks)

            Button("Paste Tracks") {
                model.pasteTracksFromClipboard()
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(!model.canPasteTracks)

            Button("Move Tracks Up") {
                model.moveSelectedTracksUp()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!model.canMoveSelectedTracksUp)

            Button("Move Tracks Down") {
                model.moveSelectedTracksDown()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!model.canMoveSelectedTracksDown)

            Button("Remove Tracks") {
                model.deleteSelectedTracks()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(!model.canCutSelectedTracks)

            Button("Export AAC...") {
                model.exportSelectedTracksToAAC()
            }
            .disabled(!model.canExportSelectedTracksToAAC)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Options...") {
                if let optionsWindow = NSApp.windows.first(where: {
                    $0.isVisible && $0.title == "Options"
                }) {
                    optionsWindow.close()
                } else {
                    openWindow(id: "options")
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
