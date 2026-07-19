#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_jobs="${COCOASPICE_BUILD_JOBS:-4}"
patch="$root/patches/vgmstream-cocoaspice.patch"

if git -C "$root/vendor/vgmstream" apply --check "$patch" >/dev/null 2>&1; then
  git -C "$root/vendor/vgmstream" apply "$patch"
elif ! git -C "$root/vendor/vgmstream" apply --reverse --check "$patch" >/dev/null 2>&1; then
  echo "vgmstream source does not match the CocoaSpice compatibility patch" >&2
  exit 1
fi

cmake -S "$root/vendor/vgmstream" -B "$root/.build/vgmstream" \
  -DBUILD_CLI=OFF \
  -DBUILD_STATIC=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DUSE_FFMPEG=OFF \
  -DUSE_MPEG=OFF \
  -DUSE_VORBIS=OFF \
  -DUSE_G7221=OFF \
  -DUSE_G719=OFF \
  -DUSE_ATRAC9=OFF \
  -DUSE_CELT=OFF \
  -DUSE_SPEEX=OFF
cmake --build "$root/.build/vgmstream" --target libvgmstream --parallel "$build_jobs"
