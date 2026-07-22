# Status of the Bloody Roar project

## Current Status

Bloody Roar (USA) was verified against the Redump-based disc image. CocoaSpice now preserves the native 37,800 Hz PlayStation CD-XA clock by resampling it into the shared 44,100 Hz output clock. The previous direct frame copy made the tracks play 7/6 too fast.

## Source Layout

- The disc data track contains `MOVIE/BGM00.XA` through `MOVIE/BGM04.XA`.
- Each source XA contains eight stereo CD-XA streams, numbered `0100` through `0107`.
- The streams are 37,800 Hz and have no embedded loop start or end points.
- The Zophar archive splits those streams into individual XA files. Its `BGM00_01006401_0000.xa` has the same 4,495,680-frame duration as source stream `BGM00.XA` / `0100`.

## Playback Behavior

- Normal playback is finite and reaches the source EOF.
- Repeat Song is the correct player behavior for a complete-song restart.
- The game executable contains separate CD-XA `1LOOP` and `REPEAT` modes, so whole-stream replay belongs to the game-player layer rather than to an XA loop marker.
- CocoaSpice Long Play must not represent these streams as having authored internal loop points.

## Preservation Boundary

The disc and split XA files remain the canonical source. Loop behavior can be preserved externally as a hash-keyed manifest that records `wholeAssetRestart` and its evidence. A vgmstream `.txtp` wrapper can express the same portable playback rule. Runtime tracing remains the final confirmation of which gameplay situations select `1LOOP` versus `REPEAT`.

The separate derived study set at `/Users/john/Downloads/audio/Derived/Bloody Roar (USA) [XA loop study]` contains the 40 extracted canonical XA files, `loop-manifest.json`, and 40 whole-asset-repeat `.txtp` candidates. The wrappers are explicitly marked as candidates and do not replace the source XA files.

## Evidence

- Source archive: `Bloody Roar (USA)` in the 2024 Redump-based Hearto PlayStation USA collection.
- Verified archive MD5: `c432edb8434d4805fd7eba921a83b215`.
- Zophar source: `Bloody Roar (EMU).zophar.zip`.
