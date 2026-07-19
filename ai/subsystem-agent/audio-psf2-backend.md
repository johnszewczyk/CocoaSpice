# PlayStation 2 PSF2 Backend

CocoaSpice routes `.psf2` and `.minipsf2` through the vendored Play! PSF core. The bridge captures its 44.1 kHz stereo sound-handler blocks into the common `AudioTrackDecoder` contract and exposes PSF tags plus the declared `length` value.

Playback and inspection are separate paths. Playlist and library metadata inspection parses the PSF container tags without constructing or resuming a Play! virtual machine. Playback creates the emulator only when a track is opened for audio output.

PSF2 library chains are resolved inside the native loader. Archive-backed tracks therefore materialize the complete archive set before opening the selected member, keeping sibling `_lib` files available without moving or rewriting source files.

The backend is built headlessly with `PSFCORE_ONLY=ON` and merged into `.build/psf2/libcocoaspice_psf2.a` by `scripts/build-psf2.sh`. It intentionally does not enable Play!'s Qt UI. Seeking resets and reloads the PSF chain, then advances the emulator to the requested frame.

The sound bridge uses a fixed one-second stereo ring buffer. Play!'s producer stops requesting work when that buffer lacks room for its next block, so a paused or stalled consumer cannot grow memory without bound. Pausing transport suspends the VM and cancels CocoaSpice's refill timer; resuming restarts both. The PSF2 build helper defaults to four parallel compile jobs and accepts `COCOASPICE_BUILD_JOBS` when a different explicit limit is needed.

When a PSF2 driver stops producing blocks at its declared length, the bridge supplies silence through the externally controlled fade window. This keeps PSF2 completion behavior aligned with the common playback timeline instead of ending abruptly at the metadata boundary.

Long Play explicitly disables that declared-length cutoff. The Play! VM continues rendering while CocoaSpice's shared finite Long Play plan owns the manual duration and external fade, matching the contract used by every other registered decoder.
