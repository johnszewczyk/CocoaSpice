# Next Mission: Standard Audio Containers

## Objective

Add streamed playback and archive-aware playlist expansion for APE and raw AAC without weakening the existing emulator-format routing.

## Scope

- M4A (including verified AAC output) and MP3 use the standard-audio decoder route with streamed PCM, duration, seeking, tags, and archive-member playback. FLAC is already on that route; raw AAC waits for fixture-backed decoder proof.
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

- Direct raw AAC and APE files stream, seek, and reach natural EOF; preserve the existing FLAC, M4A/AAC, and MP3 coverage.
- Deep scans return duration and available tags without starting playback.
- An archive M3U expands referenced sibling audio members in declared order.
- King of Fighters '95 expands to 40 rows and King of Fighters '96 to 39 rows from their local Zophar archives.
- Unsupported archive members remain excluded rather than producing empty placeholder tracks.

## First Implementation Slice

1. Complete the standard-audio registry and archive-M3U dependency model.
2. Obtain a raw AAC fixture and verify the platform decoder path before admitting `.aac`.
3. Select and package the APE bridge.
4. Add the KOF archive regression fixtures and playback/seek checks.
