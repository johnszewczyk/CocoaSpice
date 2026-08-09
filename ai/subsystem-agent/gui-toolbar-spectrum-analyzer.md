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
- The analyzer uses a ten-octave, logarithmic full-range layout from `20 Hz` through `20.48 kHz`. The selectable 10/20/40 layouts mean 1/2/4 bands per octave; each higher-detail layout splits the preceding range at its logarithmic midpoint.
- A 4,096-point real FFT samples the mixed output at 10 Hz. A Hann window limits leakage, and FFT-bin energy is integrated proportionally by each bin's overlap with a fractional-octave interval. Do not assign whole bins to one band: narrow low-frequency 40-band intervals can otherwise be empty between bins.
- The display draws at 60 FPS only while playback is active. Bars use the latest measured target directly; peak caps have a short hold and fall independently. One layer-backed AppKit surface clips every bar and paints the shared vertical gradient once per display pass; never allocate or draw a separate gradient per bar. The display timer and level publication are dormant when stopped or disabled, while the titlebar host exists only when the spectrum is enabled; an idle window does not redraw the analyzer.
- The persisted `Enable Spectrum` preference gates analyzer processing at the audio-tap boundary; disabling it stops spectrum analysis, removes the titlebar host, and clears the display without stopping playback.
- Rising bars are raw and immediate.
- Peak caps are separate from the bars and use a short hold plus exponential fall.
- Options exposes three user-facing color controls:
  - `Base`: lower bar gradient color
  - `Peak`: upper bar gradient color
  - `Cap`: peak-hold marker color

## User-Facing Technical Specification

- Placement: far-right titlebar accessory with no scrubber competing for titlebar width.
- Layout: 10, 20, or 40 vertical bands across 20 Hz–20.48 kHz.
- Bar geometry: `5 px` bar width with `1 px` gap between bars.
- Meter height: `22 px`.
- Peak cap geometry: `1 px` cap height with `1 px` gap above the live bar.
- Bar fill: vertical linear gradient from `Base` at the bottom to `Peak` at the top.
- Background: dark capsule membrane using the app's toolbar-style `20/20/20` surface.
- Frame rate: 45 frames per second.
- Rise behavior: bars snap directly to stronger incoming energy.
- Fall behavior: bars take their latest measured value directly; only peak caps fall independently.
- Peak behavior: caps snap upward instantly, hold for `100 ms`, then decay exponentially.
- Signal source: live playback mix, not fabricated demo data.
- Frequency layout: IEC/ANSI-style fractional-octave spacing from `20 Hz` through `20.48 kHz`; this is a visualization, not a certified measurement instrument.

## Rules

- Keep analyzer motion direct: measured targets set bars, and only peak caps decay.
- Do not reintroduce whole-bin band assignment or stacked smoothing stages.
- Keep toolbar placement independent from SwiftUI toolbar-item packing.
- Keep user-facing appearance controls limited to explicit persisted settings rather than hidden magic constants.
- Treat the analyzer as playback-adjacent visualization, not as part of transport logic.

## Files

- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [ToolbarSpectrumView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ToolbarSpectrumView.swift)
- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
- [AppSessionPersistence.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/AppSessionPersistence.swift)
- [PlaybackEngineTests.swift](/Users/john/Downloads/Code/CocoaSpice/Tests/CocoaSpiceTests/PlaybackEngineTests.swift)
- [PlaylistImportAndTimingTests.swift](/Users/john/Downloads/Code/CocoaSpice/Tests/CocoaSpiceTests/PlaylistImportAndTimingTests.swift)
