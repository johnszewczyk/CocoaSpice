# WIP Plan: Konami KDT1 / SdDt Sequence Playback

## Status

Implemented now: CocoaSpice recognizes Silent Hill-style `.hd` banks with an adjacent `.td` whose `SdDt` signature identifies KDT1 sequence data. The archive is materialized as a companion set and the `.hd` item is recorded as intentionally non-playable instead of logging a vgmstream decoder failure. Rendered `.msf` files in the same archive continue through vgmstream.

Not implemented: KDT1 sequence playback.

## Why This Is a Separate Feature

`SdDt` / `KDT1` holds note, timing, control, and instrument-selection events rather than audio samples. Playback needs a dedicated sequencer plus accurate interpretation of Konami driver behavior against the `.hd` instrument bank. vgmstream is a streamed-audio decoder and cannot supply this behavior.

## Required Design

1. Add a dedicated KDT1 backend and narrow native bridge; do not add sequence logic to vgmstream, Core Audio, or the generic scan executor.
2. Parse `SdDt` container sections and KDT1 events into an internal event stream.
3. Parse the compatible `.hd` sample/instrument bank and synthesize voices with the driver’s timing, pitch, volume, looping, and control semantics.
4. Keep the current signature handler as the admission gate. It must route valid rendered stream formats separately and preserve unknown `.hd` input for the existing vgmstream path.
5. Materialize the full archive set once for KDT1 scan/playback. Resolve companions only inside that root.
6. Prove fidelity against a real Silent Hill fixture: non-silent PCM, stable duration/loop behavior, seeking, and no descriptor/cache growth.

## References

- HCS research identifies `SdDt`/KDT1 as sequenced music and documents its container/header structure: <https://hcs64.com/mboard/forumlong.php?lastpage=&showthread=36833>
- The original game driver is the behavioral reference for exact event semantics.

## Acceptance Criteria

- Loose and archive-backed `.hd` + `.td` pairs render audible PCM.
- The scanner derives normal track metadata without treating sequence banks as failures.
- Playlist, drag/drop, session restore, Long Play, seek, and cancellation use the normal decoder backend contract.
- Missing or malformed companions produce a single specific item error.
