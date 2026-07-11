#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/vendor/lazyusf2"
BUILD_DIR="$ROOT_DIR/.build/lazyusf"

mkdir -p "$BUILD_DIR"

make -C "$SOURCE_DIR" clean >/dev/null 2>&1 || true
make -C "$SOURCE_DIR" liblazyusf.a \
  CC="${CC:-cc}" \
  AR="${AR:-ar}" \
  CFLAGS="-c -O2 -fPIC -I. -I$ROOT_DIR/vendor/psflib -Wno-return-type" \
  OPTS="" \
  ROPTS="-DARCH_MIN_ARM_NEON" \
  >/dev/null

cc -c -O2 -fPIC -I"$ROOT_DIR/vendor/psflib" "$ROOT_DIR/vendor/psflib/psflib.c" -o "$BUILD_DIR/psflib.o"
ar rcs "$BUILD_DIR/libpsflib.a" "$BUILD_DIR/psflib.o"
cp "$SOURCE_DIR/liblazyusf.a" "$BUILD_DIR/liblazyusf.a"
