#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_EXECUTABLE="$ROOT_DIR/dist/SPCBoy.app/Contents/MacOS/SPCBoy"
LIBRARY_ROOT_DEFAULT="$(cd "$ROOT_DIR/.." && pwd)/spcsets_extracted"

"$ROOT_DIR/build.sh"

export SPCBOY_LIBRARY_ROOT="${SPCBOY_LIBRARY_ROOT:-$LIBRARY_ROOT_DEFAULT}"
"$APP_EXECUTABLE" >/tmp/SPCBoy.log 2>&1 &

echo "Launched SPCBoy"
echo "Library root: $SPCBOY_LIBRARY_ROOT"
echo "Log: /tmp/SPCBoy.log"
