# Highly Complete miniGSF Timing

## Scope

- Why `minigsf` playback speed is tricky.
- Native GBA audio-rate behavior under `mGBA`.
- The bridge resampling contract into the app's fixed output engine.
- Seek and frame-count timebase rules.

## Current State

- The app plays through a fixed `AVAudioEngine` output format at `44_100` Hz.
- `mGBA` does not guarantee one fixed native GBA audio rate across all `gsf` or `minigsf` titles.
- GBA games can alter effective audio timing through runtime audio-register writes, especially the `SOUNDBIAS` resolution path.
- The bridge boots `mGBA` with an initial options sample rate of `32768`.
  This matches the upstream `Highly Complete` GSF path more closely than forcing `44100` into core init.
- The bridge listens to `mAVStream.audioRateChanged`.
  `mGBA` raises this callback when the effective native GBA audio rate changes during emulation.
- The bridge stores the live native rate as `activeSampleRate`.
- The bridge resamples native `mGBA` PCM into the app's requested output rate, currently `44_100` Hz.
- `playedFrames` must be counted in output frames, not native GBA frames.
- Seek milliseconds must convert against the output rate timebase, not against `activeSampleRate`.

- The bridge keeps a native `resampleBuffer` of interleaved `int16` stereo samples coming from `mGBA`.
- The render path fills that buffer from `mAudioBufferRead`.
- Output samples are produced through linear interpolation from native-rate samples into the requested output cadence.
- The render loop re-reads the live `activeSampleRate` while producing output so mid-track native-rate changes are reflected in playback speed.

## Rules

### Critical Engineering Notes

- Treat `minigsf` as variable-rate native input feeding a fixed-rate app output path.
- Never reintroduce a direct assumption that all `gsf` or `minigsf` titles are one fixed native rate.
- Keep seek and elapsed-time math aligned with output frames because the rest of the playback engine and transport logic use that frame space.
- Do not trust `core->audioSampleRate()` before the title has initialized its audio path; upstream `Highly Complete` warms the GSF core before trusting that value.
- If frame math uses native-rate frames, elapsed time and seek position drift. If rendering assumes one native rate, titles play at different wrong speeds.
- If output rate changes are ever made configurable in the future, update the bridge resampler and seek math together.

## Files

- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlaybackDecoderRouting.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackDecoderRouting.swift)
- [highlycomplete_bridge.cpp](/Users/john/Downloads/Code/CocoaSpice/Sources/CHighlyComplete/highlycomplete_bridge.cpp)
- [audio-playback-streaming.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-streaming.md)
- [audio-playback-timing.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-timing.md)
