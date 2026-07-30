#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_jobs="${COCOASPICE_BUILD_JOBS:-4}"
patch="$root/patches/vgmstream-cocoaspice.patch"
export PKG_CONFIG_PATH="/opt/homebrew/opt/ffmpeg/lib/pkgconfig:/opt/homebrew/opt/libvorbis/lib/pkgconfig:/opt/homebrew/opt/libogg/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

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
  -DCMAKE_PREFIX_PATH=/opt/homebrew \
  -DUSE_FFMPEG=ON \
  -DUSE_MPEG=OFF \
  -DUSE_VORBIS=ON \
  -DVORBISFILE_ROOT=/opt/homebrew/opt/libvorbis \
  -DVORBIS_ROOT=/opt/homebrew/opt/libvorbis \
  -DOGG_ROOT=/opt/homebrew/opt/libogg \
  -DUSE_G7221=OFF \
  -DUSE_G719=OFF \
  -DUSE_ATRAC9=OFF \
  -DUSE_CELT=OFF \
  -DUSE_SPEEX=OFF
cmake --build "$root/.build/vgmstream" --target libvgmstream --parallel "$build_jobs"
