# Audio Playback Streaming

## Scope

- Streamed decode pipeline.
- Rolling buffer scheduling.
- Seek rebuild behavior.

## Current State

- Playback is streamed in small PCM chunks into the native PCM ring buffer and consumed by `AVAudioSourceNode`.
- Playback state mutation and rolling-buffer refill now run on a dedicated serial playback queue rather than the main actor.
- Playback startup should be effectively immediate.
- Playback does not convert SPC to WAV before play.
- Decoder-native PCM is resampled at the playback boundary whenever its clock differs from the shared 44.1 kHz output clock. This preserves pitch, duration, fades, and seek timing for native-rate formats such as PlayStation CD-XA (37.8 kHz).
- Stream scheduling keeps only a small rolling buffer window ahead.
- Native-end playback modes can stream until libgme reports track completion rather than requiring a fixed prerendered duration.
- Seek rebuilds the rolling stream from the requested offset rather than rendering a replacement file.
- Old refill work is dropped when a new track, stop, or seek invalidates the prior stream generation.
- Audio-engine configuration changes rebuild the current stream from its elapsed position and preserve its playing or paused state.
- Native output state is represented by immutable value-type snapshots with explicit transport/output states, frame counters, buffer counters, underruns, end state, and stream generation.
- The Options Playback Diagnostics panel samples those snapshots at the existing 250 ms transport cadence. It shows buffered PCM headroom, underruns, and source samples beyond full scale; source clip counts are collected while the refill worker writes PCM, never in the realtime output callback.
- Frame-accounting helpers derive position from the session origin and frames supplied to output; completion helpers require planned/native completion and an empty output buffer.
- The native output boundary uses a preallocated C11 atomic stereo ring buffer and an `AVAudioSourceNode` endpoint.
- `NativePlaybackSession` owns decoder creation, generation invalidation, dedicated refill work, high-water priming, seek rebuilds, route-change recovery, and one completion callback per generation.
- Session refill passes decoder channel buffers directly into the native ring buffer without constructing intermediate Swift arrays.
- `PlaybackEngine` is the app-facing façade and delegates playback, pause/resume, seek, stop, status, spectrum tap, and completion to the native session.
- Startup, seek, and route recovery prime 8,192 frames before resuming; the refill worker grows the buffer toward its high-water mark after output starts.
- Track and seek restarts fully stop `AVAudioEngine` before clearing and refilling the ring buffer so the graph cannot preserve render-ahead state and consume the new stream before it becomes audible.

## Rules

- Never regress to full-track prerender or file conversion before playback begins.
- Preserve the small rolling queue model when refill logic changes.
- Keep streamed decode behavior separate from queue editing and metadata display.
- Preserve playback state across audio-engine configuration changes; do not treat an output-device change as user pause or stop.
- Keep realtime output contracts independent of decoder calls and UI state; the callback/output boundary consumes PCM and publishes counters while the session owns decoder work.
- Keep ring-buffer clear and telemetry reset coordinated by the session while output consumption is stopped.

## Files

- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlaybackAudioContracts.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackAudioContracts.swift)
- [RealtimePCMFrameRingBuffer.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/RealtimePCMFrameRingBuffer.swift)
- [AVAudioSourceNodeOutput.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/AVAudioSourceNodeOutput.swift)
- [NativePlaybackSession.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/NativePlaybackSession.swift)
- [cs_audio_ring_buffer.c](/Users/john/Downloads/Code/CocoaSpice/Sources/CPlaybackAudio/cs_audio_ring_buffer.c)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
