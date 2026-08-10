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
- Audio-engine configuration changes rebuild and re-prime only the output graph from the decoder's current live state. They preserve playing or paused state without elapsed-time seeking, because emulator seeks can require replaying hours of Long Play audio.
- Native output state is represented by immutable value-type snapshots with explicit transport/output states, frame counters, buffer counters, underruns, end state, and stream generation.
- All signed 16-bit decoder bridges normalize with a 32,768 divisor so the legal `Int16.min` sample maps to exactly -1.0; diagnostics only count actual out-of-range PCM, never valid full-scale minimum values.
- The Options Playback Diagnostics panel samples atomic ring-buffer counters and a small locked output heartbeat at the existing 250 ms transport cadence; it never waits for the serial playback or refill queue. It shows buffered PCM headroom, output heartbeat health, underruns, and source samples beyond full scale. Output health becomes stalled after two seconds without source-node render requests while transport is playing; it identifies a local graph stall but cannot diagnose radio/codec/speaker failures after Core Audio. Source clip counts are collected while the refill worker writes PCM, never in the realtime output callback.
- Frame-accounting helpers derive position from the session origin and frames supplied to output; completion helpers require planned/native completion and an empty output buffer.
- The native output boundary uses a preallocated C11 atomic stereo ring buffer and an `AVAudioSourceNode` endpoint.
- The shared output graph routes `AVAudioSourceNode` through one ten-band `AVAudioUnitEQ` before the main mixer. Equalizer mutation stays on the playback queue and applies before the mixer spectrum tap, so every decoder shares the same post-decode processing path.
- Mono mode is a persisted output policy. The refill worker averages decoded left/right PCM and writes that one sample to both ring-buffer channels; the realtime source-node callback remains a ring-buffer read only.
- Decoder loop policy is construction-time state for some backends. Timing reconfiguration therefore rebuilds only the active decoder stream and seeks it to the current rendered position; it must never use the ordinary new-track restart path.
- PlayStation PSF playback supplies real PCM through CocoaSpice's shared finite fade window. The PSF bridge must not replace post-tag-length audio with silence, because the external envelope owns that final fade.
- Native transport operations use one render-boundary transition policy: an atomic 24 ms linear de-click envelope applies sample-by-sample after ring-buffer read, graph/decoder replacement occurs only after it reaches silence, then a fresh primed source restores over the same envelope. Every fresh source, including the first start after launch/Stop and output-route recovery, begins muted. The persisted App Volume remains at the final mixer and never changes during transitions. It covers pause/resume, seek, stop, track changes, and Long Play decoder reconfiguration without rewriting track PCM or changing system volume.
- `NativePlaybackSession` keeps an absolute session-start frame separately from the per-generation ring-buffer read counter. Decoder/graph rebuilds (including Long Play changes) must restore that anchor before publishing elapsed time; otherwise a visually reset clock makes the following Long Play change seek to zero.
- The optional toolbar spectrum uses a 4,410-frame mixer tap (10 Hz at 44.1 kHz) and a 4,096-point real FFT. 10/20/40 bars mean 1/2/4 bands per octave from 20 Hz through 20.48 kHz. A fixed AppKit view draws all bars in one pass at 60 FPS; do not restore a SwiftUI `ForEach` titlebar graph, because its per-bar layout dominates CPU. Disabled/stopped spectrum removes the tap and timer.
- Archive playback materialization is policy-owned. Cache-on uses a durable 2 GB/4 GB/8 GB/16 GB LRU store (2 GB default); cache-off uses an isolated disposable root that is discarded when playback stops. Both modes reserve 1 GB free disk space and reject a materialization that cannot fit the active limit. Scan scratch remains separate and is reclaimed on the next launch if an interrupted prior scan stranded a root.
- `ZipArchiveSupport.cacheSummary()` reports the selected materialization root's file count, byte total, and free capacity from its actual filesystem volume. The Options Cache panel presents that snapshot; availability is informational, while `prepareDurableCacheWrite` remains the authoritative admission check.
- The six-second end fade is a persisted Playback preference. Disabling it passes a zero-second fade into the timing plan so metadata-timed tracks use the decoder's native ending.
- Faded Skip is a separate persisted Playback preference. When enabled, the first Next/Previous command begins a non-destructive output envelope on the current generation and schedules one adjacent request after the End Fade duration. A second command cancels that task and uses ordinary short de-click replacement. Natural completion ignores auto-advance while a Faded Skip token is active so the scheduled request remains single-flight.
- `NativePlaybackSession` owns decoder creation, generation invalidation, dedicated refill work, high-water priming, seek rebuilds, route-change recovery, and one completion callback per generation.
- Session refill passes decoder channel buffers directly into the native ring buffer without constructing intermediate Swift arrays.
- `PlaybackEngine` is the app-facing façade and delegates playback, pause/resume, seek, stop, status, spectrum tap, and completion to the native session.
- Startup, seek, and route recovery prime 8,192 frames before resuming; the refill worker grows the buffer toward its high-water mark after output starts.
- Normal track and seek replacements keep `AVAudioEngine` and the device output warm at zero transport gain. The ring-buffer reader rejects any in-flight pre-clear read, so a stale callback yields silence instead of republishing old PCM while the next stream is primed. Only output-route recovery or a user Stop resets the graph.

## Rules

- Never regress to full-track prerender or file conversion before playback begins.
- Preserve the small rolling queue model when refill logic changes.
- Keep streamed decode behavior separate from queue editing and metadata display.
- Preserve playback state across audio-engine configuration changes; do not treat an output-device change as user pause or stop.
- Keep realtime output contracts independent of decoder calls and UI state; the callback/output boundary consumes PCM and publishes counters while the session owns decoder work.
- Keep ring-buffer clear and telemetry reset coordinated by the session while output consumption is stopped.
- Every track, seek, and stop transition must stop and reset the output graph before clearing or refilling PCM; an in-flight read must never republish pre-clear audio into the next stream generation.

## Files

- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlaybackAudioContracts.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackAudioContracts.swift)
- [RealtimePCMFrameRingBuffer.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/RealtimePCMFrameRingBuffer.swift)
- [AVAudioSourceNodeOutput.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/AVAudioSourceNodeOutput.swift)
- [NativePlaybackSession.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/NativePlaybackSession.swift)
- [cs_audio_ring_buffer.c](/Users/john/Downloads/Code/CocoaSpice/Sources/CPlaybackAudio/cs_audio_ring_buffer.c)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
