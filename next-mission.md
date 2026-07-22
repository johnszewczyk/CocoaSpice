# Next Mission: Standard Audio Containers

## Objective

Add streamed playback and archive-aware playlist expansion for FLAC, APE, AAC, and MP3 without weakening the existing emulator-format routing.

## Scope

- FLAC, AAC, and MP3 use a standard-audio decoder route with streamed PCM, duration, seeking, tags, and archive-member playback.
- APE uses a dedicated lossless decoder bridge that produces the same PCM contract.
- Archive M3U files are dependency manifests: materialize the M3U and every referenced audio member as one selected archive set, preserve M3U order, and emit one playlist row per referenced member.
- Direct standard-audio files and archive members share the same metadata and playback route.

## Constraints

- Keep game-music decoder registration separate from standard-audio registration.
- Do not convert complete tracks to WAV before playback.
- Keep the rolling PCM output path, seeking, Repeat Song, diagnostics, and archive provenance intact.
- Preserve source archives and write derived extraction output separately.
- APE requires a maintained native decoder with licensing suitable for CocoaSpice distribution; extension admission must wait for that bridge.

## Acceptance Checks

- Direct FLAC, APE, AAC, and MP3 files stream, seek, and reach natural EOF.
- Deep scans return duration and available tags without starting playback.
- An archive M3U expands referenced sibling audio members in declared order.
- King of Fighters '95 expands to 40 rows and King of Fighters '96 to 39 rows from their local Zophar archives.
- Unsupported archive members remain excluded rather than producing empty placeholder tracks.

## First Implementation Slice

1. Add the standard-audio registry and archive-M3U dependency model.
2. Wire the platform decoder path for FLAC, AAC, and MP3.
3. Select and package the APE bridge.
4. Add the KOF archive regression fixtures and playback/seek checks.
