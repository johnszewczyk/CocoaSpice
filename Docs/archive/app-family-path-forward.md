# App-Family Path Forward

## Current Boundary

ScanSong remains a separate application and the sole schema-23 catalog
writer. CocoaSpice and SPCBoy each use their own strict read-only readers.
Neither player contains a scanner/writer implementation or stages a
ScanSong executable. Each player owns its own playlist, UI,
archive-materialization, and playback-client work.

`VGMBoyKit` is bundled in process by native frontends. It is not a server,
catalog component, or metadata service. It owns decoding, timing, audio output,
equalizer, Long Play, transport safety, and diagnostics through a versioned
control surface. Frontends own queue policy, repeat, shuffle, catalogs, and UI.

## SPCBoy Read-Only Boundary

SPCBoy has no JavaScript catalog scanner, writer, staging database,
root-mutation service, ScanSong client, or staged ScanSong executable.
Choosing a catalog opens it with SPCBoy's own SQLite worker in OS-level
read-only/query-only mode, checks the schema version and required tables,
returns stored catalog tallies, and closes the validation reader. No fallback
database and no writer capability. Scan-log display remains a read-only
presentation of catalog rows, not a scanner feature.

## UI and Platform Direction

The SPCBoy interface is a web renderer, but its current `window.spcBoy` API is
an Electron preload contract that combines catalog queries, filesystem and
archive operations, app windows, settings persistence, and the old playback
backend. It cannot be attached to CocoaSpice as an interchangeable skin yet.

First extract versioned snapshots and typed commands for CocoaSpice playlist
and database-browser state, preserving its native performance-sensitive sidebar
loader. Then define the same host-neutral product contracts for the SPCBoy web
renderer. The renderer can be shared only after it calls that narrow contract,
not Electron APIs directly.

On macOS, a Swift host may render that web UI in `WKWebView` and call the same
CocoaSpice/VGMBoyKit services. On Windows, Swift plus `WKWebView` is not a
shipping route: WKWebView is Apple-only. Keep Electron as the supported Windows
host while the renderer contract is extracted. A later Windows host can use
WebView2 with a native host and the same web assets; it must link a
cross-platform playback core rather than CocoaSpice's macOS SwiftUI app.

## Migration Gates

1. Keep SPCBoy's independent read-only catalog validation covered by the
   canonical-reader test; do not restore an external scanner validation bridge.
2. Bring VGMBoyKit to demonstrated SPCBoy playback parity before any replacement:
   automatic lock-free 10 ms transport de-click envelope, required format and
   decoder coverage, Long Play/timing, equalizer, diagnostics, and fixture
   proof. Do not regress a working SPCBoy path for architecture alone.
3. Finish CocoaSpice's host-neutral contracts for playlist and database-browser
   selection after its existing Options and main-playback surfaces. Do not
   replace the accepted cached sidebar projection with a web-shaped loader.
4. Replace renderer-specific calls with a documented snapshot/command/event
   bridge, keeping filesystem, archive materialization, catalog reading, and
   playback native to each host.
5. Use the shared renderer in a macOS `WKWebView` host first if desired; retain
   Electron for Windows until a WebView2 host and cross-platform core have
   equivalent automated and manual playback proof.
