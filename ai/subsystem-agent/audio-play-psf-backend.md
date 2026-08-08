# Play! PSF-Family Backend

## Scope

Native PlayStation PSF/miniPSF and PlayStation 2 PSF2/miniPSF2 inspection and streamed playback.

## Ownership

CocoaSpice routes PlayStation `.psf` and `.minipsf` plus PlayStation 2 `.psf2` and `.minipsf2` through the vendored Play! PSF core. One bridge captures its 44.1 kHz stereo sound-handler blocks into the common `AudioTrackDecoder` contract and exposes the validated PSF platform, tags, and declared `length` value.

Playback and inspection are separate paths. Playlist and library metadata inspection parses the PSF container tags without constructing or resuming a Play! virtual machine. Playback creates the emulator only when a track is opened for audio output.

## Invariants

PSF-family library chains are resolved inside the native loader. Archive-backed tracks therefore materialize the complete archive set before opening the selected member, keeping sibling `_lib` and PSFLIB files available without moving or rewriting source files. PSFLIB is never registered as a playable extension.

The backend is built headlessly with `PSFCORE_ONLY=ON` and merged into `.build/play-psf/libcocoaspice_play_psf.a` by `scripts/build-play-psf.sh`. It intentionally does not enable Play!'s Qt UI. Seeking resets and reloads the PSF chain, then advances the emulator to the requested frame.

## Concurrency

The sound bridge uses a fixed one-second stereo ring buffer. Play!'s producer stops requesting work when that buffer lacks room for its next block, so a paused or stalled consumer cannot grow memory without bound. The first read allows up to five seconds for a newly loaded PSF VM to produce PCM; later starved reads retain the 250 ms bound. This preserves startup for slower PSF programs while keeping ordinary decoder stalls finite. Pausing transport suspends the VM and cancels CocoaSpice's refill timer; resuming restarts both. The build helper defaults to four parallel compile jobs and accepts `COCOASPICE_BUILD_JOBS` when a different explicit limit is needed.

## Lifecycle

The bridge continues supplying real PCM after a declared PSF tag length while the shared finite playback plan applies its external fade. Do not substitute silence here: it fades silence and leaves an audible transition at the actual stream handoff.

Long Play explicitly disables that declared-length cutoff for both PSF generations. The Play! VM continues rendering while CocoaSpice's shared finite Long Play plan owns the manual duration and external fade, matching the contract used by every other registered decoder.

## Files

- [play_psf_bridge.h](/Users/john/Downloads/Code/CocoaSpice/Sources/CPlayPSF/include/play_psf_bridge.h)
- [play_psf_bridge.cpp](/Users/john/Downloads/Code/CocoaSpice/Sources/CPlayPSF/play_psf_bridge.cpp)
- [PlayPSFDecoder.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayPSFDecoder.swift)
- [build-play-psf.sh](/Users/john/Downloads/Code/CocoaSpice/scripts/build-play-psf.sh)
