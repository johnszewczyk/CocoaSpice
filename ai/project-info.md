# Project Info

## Product

- `CocoaSpice` is a native macOS audio frontend for game-music formats.
- Current decoder families include `libgme`, `libopenmpt` for tracker modules, `libvgm`, `Highly Complete` for GBA PSF-family playback, `Highly Theoretical` for Sega Saturn SSF-family playback, `lazyusf2` for Nintendo 64 USF-family playback, the Nintendo DS 2SF backend, `vgmstream` for native streamed game audio, and Play! for PlayStation PSF/miniPSF plus PlayStation 2 PSF2/miniPSF2.
- The current product split is a scanned `Database` browser on the left and an editable `Playlist` on the right.

## Major Components

- Main shell and toolbar.
- Playlist and queue operations.
- Database browsing and scan roots.
- Playback, transport, timing, and export.
- Persistence and async task ownership.
- Build and runtime packaging.

## Task Routing

Human-facing behavior:

- Main shell: [main-shell.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-human/main-shell.md)
- Playlist: [playlist.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-human/playlist.md)
- Playback: [playback.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-human/playback.md)
- Supported formats: [supported-formats.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-human/supported-formats.md)
- Database browser: [database-browser.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-human/database-browser.md)
- Options: [options.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-human/options.md)
- Audio export: [audio-export.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-human/audio-export.md)

Agent engineering notes:

- Sister-app behavioral conformance with SPCBoy: [cocoaspice-spcboy-conformance.md](/Users/john/Downloads/Code/DocMan/Docs/cocoaspice-spcboy-conformance.md)
- Sister-app scanner architecture, policy, and remaining validation: [cocoaspice-spcboy-scanner-investigation.md](/Users/john/Downloads/Code/DocMan/Docs/cocoaspice-spcboy-scanner-investigation.md)
- Playback backend routing: [audio-playback-backend-routing.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-backend-routing.md)
- Format support matrix: [audio-format-support.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-format-support.md)
- Highly Complete lifecycle and timing: [audio-highly-complete-bridge-lifecycle.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-bridge-lifecycle.md), [audio-highly-complete-minigsf-timing.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-minigsf-timing.md)
- Highly Complete failure boundaries: [audio-highly-complete-runtime-failure-modes.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-runtime-failure-modes.md)
- Codec intake and policy: [audio-libgme-format-intake.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-libgme-format-intake.md)
- SPC scanner metadata shortcuts: [audio-spc-metadata-scan.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-spc-metadata-scan.md)
- Nintendo DS 2SF backend: [audio-2sf-backend.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-2sf-backend.md)
- Play! PSF-family backend: [audio-play-psf-backend.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-play-psf-backend.md)
- Playback streaming, transport, and timing: [audio-playback-streaming.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-streaming.md), [audio-playback-transport.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-transport.md), [audio-playback-timing.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-timing.md)
- Database ownership: [library-browser-database.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/library-browser-database.md), [shared-catalog-boundary.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/shared-catalog-boundary.md), [database-sidebar-presentation.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/database-sidebar-presentation.md)
- Playlist ownership and formats: [playlist-queue-core.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/playlist-queue-core.md), [playlist-file-formats.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/playlist-file-formats.md), [gui-playlist-columns.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/gui-playlist-columns.md), [gui-playlist-selection-operations.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/gui-playlist-selection-operations.md)
- App state, async work, and packaging: [app-session-persistence.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/app-session-persistence.md), [async-task-ownership.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/async-task-ownership.md), [build-runtime-bundle.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/build-runtime-bundle.md)
- Remaining engineering notes: [subsystem-agent/](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/)

## Local Rules

- Human subsystem notes describe only what users can see and do.
- Agent subsystem notes describe only current engineering constraints and ownership facts.
- Keep codec notes separate from database and playlist behavior.
- Keep critical Highly Complete engineering notes current, but never write them as historical fix reports.
- Keep each decoder behind the app-owned `AudioTrackDecoder` and `AudioFileInspector` interfaces; format intake and backend ownership must remain separate from transport and timing.
- Decoder registration is a static plugin registry today; adding a module should add one backend target, one bridge, and one registry entry rather than expand scanner or transport conditionals.
- Keep the UI native and simple before inventing custom chrome.

## Human Docs

- `Docs/` is the human-side folder.
- `Docs/` is not default intake.
