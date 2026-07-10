# Audio Playback Streaming

## Scope

- Streamed decode pipeline.
- Rolling buffer scheduling.
- Seek rebuild behavior.

## Current State

- Playback is streamed in small PCM chunks into `AVAudioPlayerNode`.
- Playback state mutation and rolling-buffer refill now run on a dedicated serial playback queue rather than the main actor.
- Playback startup should be effectively immediate.
- Playback does not convert SPC to WAV before play.
- Stream scheduling keeps only a small rolling buffer window ahead.
- Native-end playback modes can stream until libgme reports track completion rather than requiring a fixed prerendered duration.
- Seek rebuilds the rolling stream from the requested offset rather than rendering a replacement file.
- Old refill work is dropped when a new track, stop, or seek invalidates the prior stream generation.
- Audio-engine configuration changes rebuild the current stream from its elapsed position and preserve its playing or paused state.

## Rules

- Never regress to full-track prerender or file conversion before playback begins.
- Preserve the small rolling queue model when refill logic changes.
- Keep streamed decode behavior separate from queue editing and metadata display.
- Preserve playback state across audio-engine configuration changes; do not treat an output-device change as user pause or stop.

## Files

- [SPCPlaybackEngine.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/SPCPlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
