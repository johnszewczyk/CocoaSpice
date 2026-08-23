# Next Objective: Popless Playback and Faded Skip Handoff

Date: 2026-08-09

## Purpose

This is a direct implementation handoff from the recent SPCBoy transport overhaul. Its purpose is to preserve the architectural distinction that matters for CocoaSpice work:

- A **de-click envelope** is a microscopic final-output ramp that prevents a discontinuity when output is paused, stopped, or replaced.
- A **musical fade** is intentional program material, such as the user-configured six-second end fade or Faded Skip. It must keep the live source playing; it is not implemented by reloading a tail of that source.

The first prevents pops. The second preserves the actual song and avoids synthetic transition artifacts.

## Canonical Transition Model

Use a gain envelope at the final output boundary, after decoded PCM, equalizer processing, and app volume policy:

1. Before pause, stop, seek replacement, or decoder replacement, ramp output gain from its current value to zero.
2. Wait until the ramp has reached silence before invalidating PCM, changing the decoder, clearing a ring, or stopping an output unit.
3. For a fresh source, prime the new PCM first. Start at output gain zero, then ramp to unity.
4. Keep the user’s App Volume independent from this transport gain. The transport envelope must not change system volume or persisted app volume.

SPCBoy uses a 10 ms linear envelope. This is intentionally short enough to leave a track attack intact while removing the sample discontinuity that produces a click/pop. CocoaSpice already documents a 24 ms half-cosine final-mixer duck; retain that established CocoaSpice policy unless audible testing shows a reason to alter it. The important invariant is the final-mixer/output placement and the fact that the source is not re-decoded or rewritten merely to de-click it.

## SPCBoy Implementation

### Native-session output envelope

`AudioEngine` now owns a transport-only gain separate from its app-volume and EQ settings. The Core Audio callback applies the ramp to the exact samples about to reach the device.


The helper bridge stays narrow:

- [native-audio-tools.js](/Users/john/Downloads/Code/VGMMan/SPCBoy/electron/native-audio-tools.js) exposes `rampNativePlaybackGain()` and `unloadNativePlayback()`.
- [main.js](/Users/john/Downloads/Code/VGMMan/SPCBoy/electron/main.js) carries those through IPC.
- [preload.js](/Users/john/Downloads/Code/VGMMan/SPCBoy/electron/preload.js) exposes only the renderer-safe calls.

### Warm native replacement

Normal native track replacement no longer closes the helper/output runtime between tracks:

1. The outgoing stream de-clicks to silence.
2. `player-unload` drops the old decoder and clears stale PCM while retaining the live Core Audio output unit at zero gain.
3. The next decoder is built and primed against that warm runtime.
4. `player-play` restores gain over 10 ms.

This is specifically different from “leave stale PCM in a ring.” The old decoder and ring data are still invalidated; only the output runtime is retained. The result is no device-level close/reopen discontinuity and no stale-audio leak.

Relevant implementation: [SPCBoy renderer transition coordinator](/Users/john/Downloads/Code/VGMMan/SPCBoy/web/app-playback.js).

### Renderer-PCM equivalent

Renderer-decoded formats need the same behavior even though they do not use the native helper. SPCBoy adds a dedicated `GainNode` after the normal renderer master gain:

- `startRendererTransportGain()` schedules a zero-to-unity ramp at the scheduled start time.
- `fadeRendererTransportGain()` schedules the transport fade to zero.
- `fadeActiveOutput()` dispatches the correct native or renderer envelope, then waits only for the requested envelope duration before destructive transition work.

See [app-playback.js](/Users/john/Downloads/Code/VGMMan/SPCBoy/web/app-playback.js). This preserves equalizer and app-volume semantics while making OpenMPT/standard-audio renderer paths follow the same de-click rule as native paths.

## Faded Skip

### Required behavior

With Queued Skips enabled, the first Previous/Next press while a track is playing must:

1. Keep the current decoder and current output channel alive.
2. Apply the configured Faded Skip duration to the live final-output gain.
3. Continue decoding/playing the current source throughout that fade.
4. Advance only after the fade reaches zero.

It must not seek/reload the current track at the current position with a synthetic short duration. That old approach causes an audible discontinuity at the moment it restarts and can duplicate, skip, or abruptly change program material.

### SPCBoy lifecycle

- `playAdjacent()` records a queued skip and calls `fadeActiveOutput(fadeDurationMs)` against the existing source.
- A timer invokes the same single-flight `finalizePlaybackEnded()` path used by normal natural endings. This prevents a timer/end-of-track race from advancing twice.
- `finalizePlaybackEnded()` stops/unloads only after silence, selects the requested neighbor, and preserves warm native output when the next backend is native.
- A second Previous/Next during the active Faded Skip cancels the long fade, uses only the 10 ms de-click, then advances immediately.

Direct implementation: [Faded Skip coordinator](/Users/john/Downloads/Code/VGMMan/SPCBoy/web/app-playback.js).

### CocoaSpice implications

CocoaSpice already has one final-mixer transition policy in its playback backend. If Faded Skip is added or repaired there, it should be a state in that same session-owned transition policy:

- Store a pending adjacent-track request with the session generation.
- Schedule the ordinary user-selected fade on the final mixer while preserving the current decoder/session.
- Route completion through the same serialized end-of-track path used by natural completion.
- Treat a second skip as cancellation plus a short de-click, not another long fade or reload.
- Clear/replace PCM only after the final mixer has reached silence.

Do not implement it as a `seek(currentPosition) + shortened playback plan` operation. That is a decoder/stream rebuild and necessarily risks the audible attack/discontinuity the feature is meant to avoid.

## Regression Checks

Use real audible fixtures, not only state assertions:

1. Pause and resume at a non-zero, high-amplitude waveform point: no click at pause or resume.
2. Stop at the same point: no click; the next fresh start begins normally.
3. Skip repeatedly between native tracks: no click and no stale PCM from the prior source.
4. Skip native → renderer and renderer → native: same result.
5. Enable Faded Skip with six seconds: the current song audibly continues and fades exactly once; it does not restart at the press position.
6. Press skip again during that fade: transition advances immediately without a second long fade or double advance.
7. Let a Faded Skip reach a natural track ending near the same time: exactly one adjacent track starts.
8. Verify the first transient/attack of the next track remains intact; the de-click ramp must be restricted to the final output gain, not baked into decoded track PCM.

## SPCBoy Verification Completed

- Rebuilt `native/libgme-tool` after the native output-envelope and warm-unload changes.
- `npm run check` passed.
- `npm test` passed: 74 tests passed; 1 corpus-dependent compatibility test skipped when no corpus path was supplied.

The remaining required validation is an audible in-app pass over representative native and renderer formats.
