#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_jobs="${COCOASPICE_BUILD_JOBS:-4}"
patch="$root/patches/vgmstream-cocoaspice.patch"
source_dir="$root/vendor/vgmstream"
build_dir="$root/.build/vgmstream"
library="$build_dir/src/libvgmstream.a"
stamp="$build_dir/cocoaspice-inputs.sha256"
export PKG_CONFIG_PATH="/opt/homebrew/opt/ffmpeg/lib/pkgconfig:/opt/homebrew/opt/libvorbis/lib/pkgconfig:/opt/homebrew/opt/libogg/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

if git -C "$source_dir" apply --check "$patch" >/dev/null 2>&1; then
  git -C "$source_dir" apply "$patch"
elif ! git -C "$source_dir" apply --reverse --check "$patch" >/dev/null 2>&1; then
  echo "vgmstream source does not match the CocoaSpice compatibility patch" >&2
  exit 1
fi

input_signature() {
  {
    printf '%s\n' 'CocoaSpice vgmstream build inputs v1'
    printf '%s\n' 'BUILD_CLI=OFF BUILD_STATIC=ON BUILD_SHARED_LIBS=OFF USE_FFMPEG=ON USE_MPEG=OFF USE_VORBIS=ON USE_G7221=OFF USE_G719=OFF USE_ATRAC9=OFF USE_CELT=OFF USE_SPEEX=OFF'
    shasum -a 256 "$0" "$patch"
    git -C "$source_dir" rev-parse HEAD
    git -C "$source_dir" diff --name-only -z HEAD |
      while IFS= read -r -d '' path; do
        if [[ -f "$source_dir/$path" ]]; then
          shasum -a 256 "$source_dir/$path"
        else
          printf 'missing tracked input %s\n' "$path"
        fi
      done
    git -C "$source_dir" ls-files --others --exclude-standard -z |
      while IFS= read -r -d '' path; do
        shasum -a 256 "$source_dir/$path"
      done
    cmake --version | head -n 1
    cc --version | head -n 1
    pkg-config --modversion libavcodec vorbis ogg
  } | shasum -a 256 | awk '{ print $1 }'
}

signature="$(input_signature)"
if [[ "${COCOASPICE_REBUILD_VGMSTREAM:-0}" != "1" && -f "$library" && -f "$stamp" && "$(<"$stamp")" == "$signature" ]]; then
  echo "vgmstream native build is current."
  exit 0
fi

cmake -S "$source_dir" -B "$build_dir" \
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
cmake --build "$build_dir" --target libvgmstream --parallel "$build_jobs"
printf '%s\n' "$signature" > "$stamp"
