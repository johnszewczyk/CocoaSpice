# GUI Main Shell

## Scope

- Main window shell.
- Left and right pane roles.
- Toolbar transport row.
- Bottom status bar.

## Current State

- The main window is a two-pane native split view.
- The left pane is the source browser surface.
- The right pane is the active editable queue.
- The temporary startup-isolation shell has been removed; the app always boots the live native shell now.
- The top toolbar holds previous, play-pause, and next.
- A dedicated spectrum analyzer capsule is mounted at the far right of the titlebar as a separate accessory rather than being packed into the SwiftUI toolbar item flow.
- The bottom status bar shows path or status context on the left and elapsed or total time on the right.
- Empty states use native `ContentUnavailableView`.
- The app uses the standard `Command+,` shortcut for Options, and the command toggles the Options window open or closed.
- Options opens as a regular titled window rather than the special SwiftUI Settings scene.
- The Options window is fixed at `900pt` wide, starts at `600pt` tall, and permits vertical resizing.
- The Options sidebar uses a native `NavigationSplitView` with a `Components` section containing Playback, Interface, and Database.

## Rules

- Keep the shell visually native.
- Keep the left pane as the source browser and the right pane as the active queue.
- Keep transport readable without adding custom control strips.
- Any new major control must have a clear pane owner.

## Files

- [MainView.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [gui-toolbar-spectrum-analyzer.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/gui-toolbar-spectrum-analyzer.md)
- [CocoaSpiceApp.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/CocoaSpiceApp.swift)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
