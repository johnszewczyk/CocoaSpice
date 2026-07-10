#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_EXECUTABLE="$ROOT_DIR/dist/CocoaSpice.app/Contents/MacOS/CocoaSpice"
LIBRARY_ROOT_DEFAULT="$(cd "$ROOT_DIR/.." && pwd)/spcsets_extracted"

"$ROOT_DIR/build.sh"

export COCOASPICE_LIBRARY_ROOT="${COCOASPICE_LIBRARY_ROOT:-$LIBRARY_ROOT_DEFAULT}"
"$APP_EXECUTABLE" >/tmp/CocoaSpice.log 2>&1 &

echo "Launched CocoaSpice"
echo "Library root: $COCOASPICE_LIBRARY_ROOT"
echo "Log: /tmp/CocoaSpice.log"
