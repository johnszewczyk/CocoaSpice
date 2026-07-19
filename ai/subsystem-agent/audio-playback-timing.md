# Audio Playback Timing

## Scope

- Long-play behavior.
- Manual play-time behavior.
- Fade behavior.
- Metadata-derived duration planning.

## Current State

- Timing controls live in Options, not the main window.
- Options now exposes one shared playback timing section.
- Options close explicitly saves the current timing preferences.
- Timing controls remain interactive regardless of the currently playing file type.
- User-facing timing now has only two modes:
  file or plugin default playback,
  or one shared Long Play target duration.
- Long Play uses one shared manual play-time value for every supported format.
- Every decoder module admitted by `GMEFormatSupport` automatically participates in Long Play. The shared plan disables native completion, applies the manual pre-fade duration and common fade, and marks the decoder session as Long Play.
- Backends whose native cores otherwise stop at their declared duration must honor the Long Play session flag. PSF2 continues beyond its tag length, while vgmstream reopens in forced-loop/play-forever mode; CocoaSpice still owns the finite manual stop and fade.
- With Long Play disabled, playback prefers file or decoder default end behavior.
- `fadeSeconds` remains model-driven timing state and is currently `6` seconds by default.
- The active fade setting is applied to both live playback and AAC export planning.
- Timing changes restart the current track through the normal playback path after a hard playback reset.

## Rules

- Keep timing ownership separate from shell layout and transport controls.
- Keep metadata inspection separate from live streamed decode work.
- Prefer one user-facing timing model unless a backend limitation forces divergence.

## Files

- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlaybackTimingPolicy.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackTimingPolicy.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
