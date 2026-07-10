# GUI Toolbar Spectrum Analyzer

## Scope

- Titlebar-mounted spectrum display.
- Audio-analysis feed from live playback.
- User-facing animation and color behavior.
- Persistence of analyzer appearance settings.

## Current State

- The spectrum analyzer is a dedicated titlebar accessory anchored to the far right of the main window rather than a normal SwiftUI toolbar item.
- This avoids SwiftUI toolbar coalescing and gives the analyzer a stable titlebar lane of its own.
- The analyzer is fed from the live mixed playback output through `AVAudioEngine.mainMixerNode`.
- The analyzer now uses 20 log-spaced bars across a chiptune-oriented range rather than a textbook full-range EQ map.
- Current band centers are approximately `31`, `40`, `51`, `64`, `82`, `104`, `133`, `169`, `215`, `273`, `348`, `443`, `563`, `717`, `912`, `1161`, `1477`, `1879`, `2391`, and `3043` Hz.
- The display updates on a 60 Hz UI timer.
- Rising bars are raw and immediate.
- Falling bars use one light exponential settle with a `50 ms` time constant.
- Peak caps are separate from the bars and use a short hold plus exponential fall.
- Options exposes three user-facing color controls:
  - `Base`: lower bar gradient color
  - `Peak`: upper bar gradient color
  - `Cap`: peak-hold marker color

## User-Facing Technical Specification

- Placement: far-right titlebar accessory with no scrubber competing for titlebar width.
- Layout: 20 vertical bars.
- Bar geometry: `5 px` bar width with `1 px` gap between bars.
- Meter height: `22 px`.
- Peak cap geometry: `1 px` cap height with `1 px` gap above the live bar.
- Bar fill: vertical linear gradient from `Base` at the bottom to `Peak` at the top.
- Background: dark capsule membrane using the app's toolbar-style `20/20/20` surface.
- Frame rate: 60 frames per second.
- Rise behavior: bars snap directly to stronger incoming energy.
- Fall behavior: bars settle exponentially toward lower measured values with a `50 ms` time constant.
- Peak behavior: caps snap upward instantly, hold for `100 ms`, then decay exponentially.
- Signal source: live playback mix, not fabricated demo data.
- Frequency focus: approximately `31 Hz` through `3 kHz`, tuned to be more legible for retro and chiptune material than a full-range `16 kHz` spread.

## Rules

- Keep analyzer motion simple: instant rise, one light fall settle, and separate cap decay.
- Do not reintroduce stacked smoothing stages in both the audio-analysis path and the UI path.
- Keep toolbar placement independent from SwiftUI toolbar-item packing.
- Keep user-facing appearance controls limited to explicit persisted settings rather than hidden magic constants.
- Treat the analyzer as playback-adjacent visualization, not as part of transport logic.

## Files

- [MainView.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/MainView.swift)
- [ToolbarSpectrumView.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/ToolbarSpectrumView.swift)
- [SPCPlaybackEngine.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/SPCPlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/PlayerViewModel.swift)
- [OptionsView.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/OptionsView.swift)
- [AppSessionPersistence.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/AppSessionPersistence.swift)
- [SPCBoyTests.swift](/Users/john/Documents/Code/CocoaSpice/Tests/SPCBoyTests/SPCBoyTests.swift)
