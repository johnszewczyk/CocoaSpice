# Project Info

## Product

- `CocoaSpice` is a native macOS game-music playlist frontend.
- It reads a schema-23 catalog published by MediaScanner and bundles `VGMBoyKit` for playback.
- The product split is a read-only `Database` browser on the left and an editable `Playlist` on the right.

## Major Components

- Main shell and toolbar.
- Playlist and queue operations.
- Read-only database browsing and queue projections.
- VGMBoy playback controls, transport, timing, and equalizer presentation.
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

Agent engineering notes:

- Sister-app behavioral conformance with SPCBoy: [cocoaspice-spcboy-conformance.md](/Users/john/Downloads/Code/DocMan/Docs/cocoaspice-spcboy-conformance.md)
- Sister-app scanner architecture, policy, and remaining validation: [cocoaspice-spcboy-scanner-investigation.md](/Users/john/Downloads/Code/DocMan/Docs/cocoaspice-spcboy-scanner-investigation.md)
- VGMBoy playback integration: [audio-playback-backend-routing.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-backend-routing.md)
- Skin-neutral Options control boundary: [frontend-control-surface.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/frontend-control-surface.md)
- Database ownership: [library-browser-database.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/library-browser-database.md), [shared-catalog-boundary.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/shared-catalog-boundary.md), [database-sidebar-presentation.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/database-sidebar-presentation.md)
- Playlist ownership and formats: [playlist-queue-core.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/playlist-queue-core.md), [playlist-file-formats.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/playlist-file-formats.md), [gui-playlist-columns.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/gui-playlist-columns.md), [gui-playlist-selection-operations.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/gui-playlist-selection-operations.md)
- App state and async work: [app-session-persistence.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/app-session-persistence.md), [async-task-ownership.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/async-task-ownership.md)
- Remaining engineering notes: [subsystem-agent/](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/)

## Local Rules

- Human subsystem notes describe only what users can see and do.
- Agent subsystem notes describe only current engineering constraints and ownership facts.
- CocoaSpice never writes, scans, migrates, or enriches the selected MediaScanner catalog.
- Keep database browsing and queue construction separate from VGMBoy playback control.
- Format routing, decoder integration, timing, and audio output belong to VGMBoyKit; CocoaSpice must not add decoder or audio-engine implementations.
- Keep the UI native and simple before inventing custom chrome.

## Human Docs

- `Docs/` is the human-side folder.
- `Docs/` is not default intake.
