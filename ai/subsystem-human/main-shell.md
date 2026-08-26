# Main Shell

## Display

- Main window: two-pane layout.
- Left pane: database browser.
- Right pane: editable playlist.
- Main-window navigation toolbar: individual Console View, Path View,
  Favorites, and (when enabled) Local Files view items, plus a fold/unfold-all
  item beside the native sidebar disclosure control. These remain individual
  native toolbar items rather than a grouped capsule.
- Main transport toolbar: previous, play-pause, next, Long Play, repeat, random playback, and Equalizer on/off. The infinity button turns Long Play on or off.
- The sidebar begins with search and list content.
- Sidebar: shows a loading indicator while its current database view loads, keeping the main window interactive at launch. Games load first; the potentially large Files tree loads only after Files is opened.
- Status bar: elapsed time / current-track total / playlist total duration. A plus suffix means some queued tracks do not yet have a known duration.

## Options

- Options: opens with `Command+,`.
- Options: utility window sized for preference editing.

## About

- About CocoaSpice: opens from the standard App menu.
- About: identifies CocoaSpice and its bundled VGMBoy playback core. The current upstream component inventory, licenses, and source links live in VGMBoy's README.

## Files

- [MainView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [CocoaSpiceApp.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/CocoaSpiceApp.swift)
- [AboutView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/AboutView.swift)
