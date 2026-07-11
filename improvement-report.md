# CocoaSpice Audio-Core Improvement Report

## Task

Improve CocoaSpice's native playback core by adopting the strongest runtime ideas from SPCBoy while preserving CocoaSpice's native Swift architecture, decoder-module boundary, queue model, and macOS integration.

This report is a handoff for a focused implementation task. It is not a changelog and does not describe an implementation already completed.

## Recommendation

CocoaSpice should remain the application architecture we build on.

SPCBoy has the stronger low-level output runtime in a few specific areas:

- Native callback-driven output backed by a ring buffer.
- Dedicated decode/refill worker.
- Explicit buffered-frame and underrun telemetry.
- Playback position derived from audio frames supplied to the output.
- Clear native transport/output snapshots.

CocoaSpice has the stronger product architecture:

- Native SwiftUI/AppKit application structure.
- App-owned decoder interfaces shared by all format modules.
- Centralized playback timing policy.
- Decoder-independent queue and transport behavior.
- Latest-request-wins playback cancellation.
- Native media-command integration.
- Audio-engine route-change recovery.

The target is therefore a CocoaSpice-native playback core with SPCBoy-style output accounting and buffering. Do not copy SPCBoy's Electron/JavaScript ownership split.

## Current CocoaSpice Model

### Ownership

- `PlayerViewModel` owns app-facing queue, selection, timing settings, transport intent, and UI state.
- `SPCPlaybackEngine` owns the serial playback queue, `AVAudioEngine`, `AVAudioPlayerNode`, decoder session, stream scheduling, pause state, and output-configuration recovery.
- `AudioTrackDecoder` owns decoder-specific metadata, rendering, seeking, timing configuration, and end detection.
- `PlaybackDecoderFactory` routes registered extensions to decoder implementations.
- `PlaybackTimingPolicy` converts metadata and user timing preferences into a playback plan.

### Current stream path

1. The view model creates a playback request and invalidates older requests.
2. The playback engine creates a decoder through `PlaybackDecoderFactory`.
3. `SPCStreamSession` renders PCM chunks.
4. The engine schedules a small rolling window of `AVAudioPCMBuffer` objects into `AVAudioPlayerNode`.
5. Buffer-consumption callbacks refill the rolling window on the serial playback queue.
6. Playback elapsed time is currently derived primarily from wall-clock dates.

### Current strengths to preserve

- No full-track prerender before playback.
- Decoder modules remain behind app-owned interfaces.
- Queue edits remain independent from active transport state.
- Seek rebuilds the stream from the requested position.
- Stale track requests cannot enter decoder loading after a newer request wins.
- Output-device changes preserve the current track and playback state when recovery succeeds.

## SPCBoy Reference Model

The relevant reference files are:

- `native/libgme_tool.c`
- `native/audio_engine_macos.c`
- `native/ring_buffer.c`
- `web/app-playback.js`

SPCBoy's native helper primes a ring buffer, starts a dedicated decode thread, and lets the Core Audio callback consume PCM independently. The helper reports:

- Transport state.
- Output state.
- Buffered frames.
- Ring capacity.
- Callback frames.
- Frames requested.
- Frames supplied.
- Underrun count.
- Decode error and end state.

The useful idea is the separation between decoder production and realtime output consumption. The JavaScript polling and duplicated renderer/native state are not part of the target architecture.

## Target Architecture

### Native output boundary

Introduce an app-owned native output abstraction below `SPCPlaybackEngine`:

```text
PlaybackViewModel
        |
SPCPlaybackEngine / PlaybackSession
        |
NativeAudioOutput
        |
Core Audio callback + lock-free or realtime-safe PCM ring buffer
```

`NativeAudioOutput` should own:

- Audio unit or equivalent native output endpoint.
- Output format.
- Ring-buffer storage.
- Realtime callback consumption.
- Output start/stop state.
- Counters and snapshots.

The playback session should own:

- Decoder lifetime.
- Decode/refill worker.
- Playback plan.
- Stream generation.
- Seek and restart behavior.
- End-of-track detection.
- Mapping output frame counters to user-facing position.

The view model should continue to own only app-facing state and intent.

### Decoder module boundary

Keep the existing module contract:

- `AudioTrackDecoder`
- `AudioFileInspector`
- Static decoder-module registry

The output core must consume decoded PCM without knowing whether it came from libgme, libvgm, Highly Complete, lazyusf2, or a future module.

### Position authority

Make output-frame accounting the authoritative position while running:

```text
audiblePosition ~= sessionStartFrame + outputFramesSupplied / sampleRate
```

Use the decoder's played-frame count only for decode/session bookkeeping. Do not use wall-clock time as the primary progress source during active playback.

Wall-clock time may still be used for UI refresh cadence and pause-duration bookkeeping.

## Realtime Invariants

The native audio callback must:

- Perform no memory allocation.
- Perform no decoder calls.
- Perform no Swift calls.
- Avoid blocking mutex acquisition.
- Never resize or reconfigure the ring buffer.
- Always provide output silence when insufficient frames are available.
- Update only realtime-safe counters or atomics.

The decode/refill worker must:

- Own decoder calls.
- Stop producing after a generation change.
- Never mutate UI state directly.
- Refill toward a high-water mark and yield below it.
- Treat ring-buffer capacity and write results as authoritative.
- Exit cleanly before decoder destruction.

The session must:

- Invalidate the previous generation before replacing a decoder.
- Clear buffered PCM before seek, stop, route recovery, or track replacement.
- Never let old decoded PCM play after a newer request wins.
- Keep decoder lifetime longer than all worker operations that reference it.
- Publish one coherent snapshot for transport, output, position, and failure state.

## Proposed Snapshots

The native/output snapshot should contain at least:

- `transportState`: stopped, loading, paused, playing, seeking, ended, failed.
- `outputState`: unavailable, stopped, primed, running, failed.
- `trackLoaded`.
- `decodeError`.
- `reachedEnd`.
- `sampleRate`.
- `channelCount`.
- `bufferedFrames`.
- `ringBufferFrames`.
- `framesRequested`.
- `framesSupplied`.
- `underrunCount`.
- `positionFrames` or `positionMilliseconds`.
- `generation`.

Snapshots should be immutable value types at the Swift boundary. The UI can derive diagnostics and labels from them without polling decoder internals.

## Route-Change Behavior

On an audio-engine or output-device configuration change:

1. Capture the current session position from frame accounting.
2. Stop output consumption.
3. Invalidate the refill generation.
4. Clear the ring buffer.
5. Recreate or reconfigure the output endpoint.
6. Seek the decoder/session to the captured position.
7. Re-prime the ring buffer.
8. Restore playing or paused state.
9. Publish one new coherent snapshot.

If any step fails, publish a failure state and stop cleanly. Do not resume stale buffered audio.

## Seek Behavior

Seek should be an explicit session transaction:

1. Mark the session seeking.
2. Invalidate the current refill generation.
3. Stop or pause output consumption.
4. Clear all queued PCM.
5. Seek or recreate the decoder.
6. Reset output counters for the new position.
7. Prime the ring buffer.
8. Resume only if playback was active before the seek.
9. Publish the new position and state.

The progress slider must not show the old position while the seek transaction is in flight.

## Timing and End Behavior

Keep `PlaybackTimingPolicy` above the decoder and output layers.

- Fixed/manual playback plans remain app policy.
- Decoder-native endings remain decoder facts.
- Fade shaping remains a session/output concern when the decoder does not apply it internally.
- Native-end tracks must end when the decoder reports end and the output buffer drains.
- Fixed-duration tracks must end when the planned frame count is consumed and the output buffer drains.

The end event should be emitted once per generation. Queue auto-advance must consume that event rather than infer completion from a timer.

## Implementation Phases

### Phase 1: Extract contracts

- Define `NativeAudioOutput` and immutable output snapshots.
- Define session states and generation ownership.
- Add unit-testable position and completion helpers.
- Keep the existing player-node implementation behind the same internal contract while the new output path is built.

### Phase 2: Native ring-buffer output

- Add a macOS native output target using Core Audio.
- Use a realtime-safe ring buffer.
- Add priming, high-water refill, silence-on-underrun, and counters.
- Add deterministic shutdown and route-change handling.

### Phase 3: Decoder worker and session integration

- Move decoder rendering to a dedicated worker owned by the playback session.
- Replace player-node buffer scheduling as the primary production/consumption path.
- Preserve decoder module interfaces and current timing policy.
- Make frame accounting authoritative for position.

### Phase 4: Transport integration

- Route toolbar, keyboard, media commands, seek, completion, and output changes through the session state machine.
- Remove duplicate state transitions.
- Keep latest-request-wins behavior.

### Phase 5: Diagnostics and cleanup

- Add optional native playback diagnostics to the app UI or debug reporting.
- Verify no callback locks, allocations, decoder calls, or Swift calls.
- Remove obsolete rolling-player-node scheduling only after the new path is validated.
- Update subsystem documentation and third-party/runtime notes.

## Acceptance Tests

### Functional

- Play, pause, resume, stop, previous, and next.
- Rapid next/previous requests remain latest-wins.
- Seek while playing.
- Seek while paused.
- Seek near the beginning and end.
- Fixed-duration playback ends once and advances correctly.
- Native-end playback drains and advances correctly.
- Fade behavior remains correct.
- SPC, NSF, VGM, GSF, miniGSF, USF, and miniUSF continue to route through their modules.
- AAC export remains independent of live output.

### Audio-runtime

- Output starts only after a minimum PCM prime level is available.
- Underruns produce silence and increment telemetry.
- Refill resumes after the buffer drops below its low-water mark.
- Stop and replacement never allow stale PCM to play.
- Decoder destruction waits for worker shutdown.
- Route changes preserve position and play/pause state.
- Repeated route changes do not leak audio units, threads, buffers, or decoders.

### Position

- Progress follows supplied output frames rather than wall-clock drift.
- Pause does not advance position.
- Seek resets the position origin and output counters.
- Completion reports the planned or native duration consistently.

## Risks

- Realtime callback locking can create glitches even when the functional behavior is correct.
- Decoder workers can race with track replacement or route recovery if generation ownership is incomplete.
- The current lazyusf2 seek implementation is restart-and-render and may need a backend-specific optimization later.
- Core Audio route changes can invalidate the output unit or format.
- A native C output layer increases shutdown and memory-lifetime responsibility.
- Current CocoaSpice has a broad uncommitted feature set; this audio-core task should begin from a clean, committed baseline.

## Files to Start From

CocoaSpice:

- `Sources/CocoaSpice/App/SPCPlaybackEngine.swift`
- `Sources/CocoaSpice/App/PlaybackDecoderRouting.swift`
- `Sources/CocoaSpice/App/PlaybackTimingPolicy.swift`
- `Sources/CocoaSpice/App/PlayerViewModel.swift`
- `Sources/CocoaSpice/App/QueueTransportNavigation.swift`
- `Sources/CocoaSpice/App/RemoteTransportController.swift`
- `ai/subsystem-agent/audio-playback-streaming.md`
- `ai/subsystem-agent/audio-playback-transport.md`
- `ai/subsystem-agent/audio-playback-timing.md`

SPCBoy reference:

- `native/audio_engine.h`
- `native/audio_engine_macos.c`
- `native/ring_buffer.c`
- `native/libgme_tool.c`
- `web/app-playback.js`

## Definition of Done

- CocoaSpice remains native Swift/AppKit/SwiftUI at the application boundary.
- Decoder modules remain format-independent from the output engine.
- Output is driven by a native realtime-safe ring buffer and dedicated decode worker.
- Position is frame-accounted.
- Transport, seek, completion, and route changes share one session state machine.
- All acceptance tests pass.
- Current subsystem docs describe the new ownership and invariants.
