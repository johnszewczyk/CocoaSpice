#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/vendor/libvgm"
BUILD_DIR="$ROOT_DIR/.build/libvgm"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Missing vendored libvgm source at $SOURCE_DIR"
  echo "Clone it with: git clone --depth 1 https://github.com/ValleyBell/libvgm.git vendor/libvgm"
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "Missing cmake"
  echo "Install it with: brew install cmake"
  exit 1
fi

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_LIBAUDIO=NO \
  -DBUILD_PLAYER=NO \
  -DBUILD_VGM2WAV=NO \
  -DBUILD_TESTS=NO \
  -DLIBRARY_TYPE=STATIC \
  -DUSE_SANITIZERS=OFF

cmake --build "$BUILD_DIR" --target vgm-utils vgm-emu vgm-player -j 4
