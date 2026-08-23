#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/CocoaSpice.app"
LIBRARY_ROOT_DEFAULT="$(cd "$ROOT_DIR/../.." && pwd)/spcsets_extracted"

if [[ "${1:-}" == "--rebuild" ]]; then
  rm -rf "$ROOT_DIR/.build" "$ROOT_DIR/dist/CocoaSpice.app"
fi

"$ROOT_DIR/build.sh"

export COCOASPICE_LIBRARY_ROOT="${COCOASPICE_LIBRARY_ROOT:-$LIBRARY_ROOT_DEFAULT}"
open -n "$APP_BUNDLE"

echo "Launched CocoaSpice"
echo "Library root: $COCOASPICE_LIBRARY_ROOT"
echo "Bundle: $APP_BUNDLE"
