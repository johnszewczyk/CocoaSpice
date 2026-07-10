# COG Comparison Report

## Purpose

This note is a compact handoff for future agents comparing CocoaSpice against COG.

It is not meant to be a deep source audit. It captures what we already learned while improving CocoaSpice, so future work can begin from the useful conclusions instead of re-burning tokens rediscovering them.

## High-Confidence Findings

### 1. COG is not a single-decoder app for game music

COG does not use one universal backend for all retro/game-audio formats.

What we learned from the prior scout:

- COG uses `libgme` for formats like:
  `spc`, `nsf`, `nsfe`, `gbs`, `hes`, `kss`, `sap`, `sgc`, `ay`, `sfm`
- COG uses `libvgm` for:
  `vgm`, `vgz`, `gym`, `s98`, `dro`
- This matters because some `.vgz` files that fail under `libgme` play correctly in COG specifically because COG routes them to `libvgm`, not because COG has a better `libgme` integration.

### 2. COG’s VGM-family handling was ahead of ours

Before our decoder split, CocoaSpice routed VGM-family files through `libgme`, which caused real failures for some non-Sega chip logs.

Examples already validated during prior work:

- Game Boy `.vgz` that COG played
- TG16 / PC Engine `.vgz` that COG played

Conclusion:

- COG was better here because of architecture, not polish.
- We corrected this by adding a split backend model:
  `libgme` for dump/container formats,
  `libvgm` for VGM-family logged-chip formats.

### 3. COG supports ZIP more broadly than CocoaSpice currently does

COG behavior observed or discussed:

- drag and drop of `.zip` to playlist works
- browsing ZIP contents in the side pane appears supported
- ZIP interaction feels seamless enough that decompression overhead is not a visible UX problem

Our current state:

- CocoaSpice supports ZIP on the playlist import path
- archive members can become playable playlist entries
- ZIP contents are not currently indexed into the database library/sidebar

Conclusion:

- COG is ahead on library-level ZIP integration
- CocoaSpice is already on the path, but only for playlist intake

### 4. COG lacks our Long Play focus

This is one of our clearest product differentiators.

COG may have stronger breadth in some subsystems, but it does not center forced-length / Long Play behavior the way CocoaSpice does.

That means:

- we should absolutely steal stronger architecture where useful
- we should not drift into merely copying COG’s defaults where they are weaker than our product goal

## Areas Where COG Appears Stronger

### Decoder architecture

COG appears to choose pragmatic decoder specialization rather than forcing one library to do everything.

That is a good model and we have already started following it.

### ZIP UX

COG’s ZIP handling appears more mature, especially if future work confirms:

- ZIPs browsable in the side pane
- searchable entries within ZIPs
- smooth enqueue/play semantics for archive contents

### Breadth and maturity of format handling

COG has likely spent longer accumulating specialized playback paths, so it may still have:

- better edge-case handling
- better metadata interpretation in some formats
- broader per-format polish

Future agents should assume COG may still be a useful reference for:

- decoder routing
- container handling
- side-pane/archive UX
- drag/drop semantics

## Areas Where We Should Not Copy Blindly

### Long Play behavior

COG does not appear to prioritize Long Play the way CocoaSpice does.

That means COG is not the product reference for:

- forced-length policy
- loop-aware extension strategy
- per-family Long Play UX

We should use COG for structural ideas, not for the core playback philosophy.

### Feature accumulation without simplification

COG is broader and older. That can imply stronger systems, but it can also imply more historical layering.

CocoaSpice should prefer:

- cleaner routing
- fewer duplicated UI concepts
- smaller, more intentional behavior surfaces

## Areas Where CocoaSpice Has Improved or Chosen Better Direction

### Database-first library direction

We intentionally moved away from the older hard-disk browsing direction in favor of the database model.

That is a sound simplification for our app, especially given large libraries and future subtrack indexing.

### Subtrack-aware library model

We already shifted toward treating multi-track containers like NSF as playable leaves instead of pretending every file is one song.

This is the correct direction, even though it complicates the sidebar and search model.

### Split decoder path

CocoaSpice now has the beginnings of the right architecture:

- `libgme` where it fits
- `libvgm` where it fits

This is a foundational improvement and should be protected.

## Open Questions Worth Future COG Study

These were not fully resolved in prior work and are good future comparison targets:

- How exactly does COG represent ZIP contents in its library/indexing layer?
- Does COG flatten archive entries into its search index, or keep container-aware search results?
- How does COG model subsongs in the library UI versus playlist UI?
- Does COG cache playlist or folder loads aggressively, or is its speed mostly architectural?
- Which of COG’s faster-feeling interactions are true backend wins versus just lighter UI work?

## Practical Guidance For Future Agents

If you are studying COG for improvements, prioritize these topics first:

1. archive and ZIP indexing model
2. side-pane expansion and search for containers/subtracks
3. queue and playlist population semantics
4. decoder routing philosophy
5. drag/drop behavior and archive ingestion

Do not spend early effort re-proving:

- that COG uses `libvgm` for `vgm` / `vgz` / `gym` / `s98`
- that COG lacks our Long Play emphasis
- that ZIP support is an area where COG is ahead

Those are already established enough for planning purposes.

## Bottom Line

COG is a strong reference for systems architecture, decoder specialization, and archive UX.

COG is not the reference product for CocoaSpice’s central differentiator, which is Long Play.

The best path is:

- borrow superior structure aggressively
- preserve CocoaSpice’s Long Play-first identity
- keep simplifying our own model where COG’s broader history may have accumulated extra complexity
