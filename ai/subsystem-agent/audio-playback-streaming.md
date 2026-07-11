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
- Native output state is represented by immutable value-type snapshots with explicit transport/output states, frame counters, buffer counters, underruns, end state, and stream generation.
- Frame-accounting helpers derive position from the session origin and frames supplied to output; completion helpers require planned/native completion and an empty output buffer.
- The Phase 2 native output boundary uses a preallocated C11 atomic stereo ring buffer and an `AVAudioSourceNode` endpoint; it is independently feedable and remains behind the existing player-node path until session integration is validated.
- `NativePlaybackSession` now owns decoder creation, generation invalidation, dedicated refill work, high-water priming, seek rebuilds, and one completion callback per generation; the existing `SPCPlaybackEngine` façade has not delegated to it yet.

## Rules

- Never regress to full-track prerender or file conversion before playback begins.
- Preserve the small rolling queue model when refill logic changes.
- Keep streamed decode behavior separate from queue editing and metadata display.
- Preserve playback state across audio-engine configuration changes; do not treat an output-device change as user pause or stop.
- Keep realtime output contracts independent of decoder calls and UI state; the callback/output boundary will consume PCM and publish counters while the session owns decoder work.
- Keep ring-buffer clear and telemetry reset coordinated by the session while output consumption is stopped.

## Files

- [SPCPlaybackEngine.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/SPCPlaybackEngine.swift)
- [PlaybackAudioContracts.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackAudioContracts.swift)
- [RealtimePCMFrameRingBuffer.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/RealtimePCMFrameRingBuffer.swift)
- [AVAudioSourceNodeOutput.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/AVAudioSourceNodeOutput.swift)
- [NativePlaybackSession.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/NativePlaybackSession.swift)
- [cs_audio_ring_buffer.c](/Users/john/Documents/Code/CocoaSpice/Sources/CPlaybackAudio/cs_audio_ring_buffer.c)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
