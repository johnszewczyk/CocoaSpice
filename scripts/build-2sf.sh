#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/vendor/2sf2wav"
BUILD_DIR="$ROOT_DIR/.build/2sf"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Missing vendored 2sf2wav source at $SOURCE_DIR"
  exit 1
fi

mkdir -p "$BUILD_DIR"
make -C "$SOURCE_DIR" lib2sf.a
cp "$SOURCE_DIR/lib2sf.a" "$BUILD_DIR/lib2sf.a"
