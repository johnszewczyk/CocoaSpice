import AppKit
import SwiftUI

extension Notification.Name {
    static let cocoaSpiceResetWindows = Notification.Name("CocoaSpice.resetWindows")
}

@MainActor
private enum CocoaSpiceWindowActivation {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let notifiedWindow = notification.object as? NSWindow else { return }
            Task { @MainActor [weak notifiedWindow] in
                guard let window = notifiedWindow,
                      window.title == "CocoaSpice" else { return }
                NSApp.activate(ignoringOtherApps: true)
                for appWindow in NSApp.windows where appWindow.isVisible {
                    appWindow.orderFrontRegardless()
                }
            }
        }
    }
}

@MainActor
private enum CocoaSpiceWindowDefaults {
    static func resetAll() {
        let defaults: [(String, NSSize)] = [
            ("CocoaSpice", NSSize(width: 1100, height: 720)),
            ("Options", NSSize(width: 800, height: 600)),
            ("About CocoaSpice", NSSize(width: 560, height: 620))
        ]
        for window in NSApplication.shared.windows {
            guard let match = defaults.first(where: { window.title == $0.0 }) else { continue }
            window.setFrame(centeredFrame(size: match.1, on: window.screen), display: true, animate: false)
            window.setFrameAutosaveName("")
        }
    }

    private static func centeredFrame(size: NSSize, on screen: NSScreen?) -> NSRect {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }
}

@main
struct CocoaSpiceApp: App {
    @NSApplicationDelegateAdaptor(CocoaSpiceAppDelegate.self) private var appDelegate
    @State private var model = PlayerViewModel()

    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        CocoaSpiceWindowActivation.install()
    }

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .onAppear {
                    appDelegate.model = model
                }
                .onOpenURL { url in
                    model.openPlaylistM3U(at: url)
                }
                .onDisappear {
                    model.saveSessionStateNow()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.saveSessionStateNow()
                }
                .onReceive(NotificationCenter.default.publisher(for: .cocoaSpiceResetWindows)) { _ in
                    CocoaSpiceWindowDefaults.resetAll()
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
        .defaultSize(width: 800, height: 600)
        .windowResizability(.contentMinSize)

        Window("About CocoaSpice", id: "about") {
            AboutView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentSize)
    }
}

@MainActor
private final class CocoaSpiceAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: PlayerViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.saveSessionStateNow()
        return .terminateNow
    }
}

private struct CocoaSpiceCommands: Commands {
    @Bindable var model: PlayerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About") {
                openWindow(id: "about")
            }
        }

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
            Button("Toggle Favorite") {
                model.toggleFavorites()
            }
            .keyboardShortcut("d", modifiers: .command)

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
