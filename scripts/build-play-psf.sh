#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/.build/play-psf"
build_jobs="${COCOASPICE_BUILD_JOBS:-4}"
patch="$root/patches/play-psfcore-only.patch"

if git -C "$root/vendor/play" apply --check "$patch" >/dev/null 2>&1; then
  git -C "$root/vendor/play" apply "$patch"
elif ! git -C "$root/vendor/play" apply --reverse --check "$patch" >/dev/null 2>&1; then
  echo "Play! source does not match the CocoaSpice PSF-family patch" >&2
  exit 1
fi

cmake -S "$root/vendor/play" -B "$build" \
  -DBUILD_PLAY=OFF \
  -DBUILD_PSFPLAYER=ON \
  -DBUILD_TESTS=OFF \
  -DBUILD_AOT_CACHE=OFF \
  -DUSE_AOT_CACHE=OFF \
  -DPSFCORE_ONLY=ON
cmake --build "$build" --target PsfCore --parallel "$build_jobs"

libtool -static -o "$build/libcocoaspice_play_psf.a" \
  "$build/tools/PsfPlayer/Source/libPsfCore.a" \
  "$build/tools/NamcoSys147NANDTools/Source/libPlayCore.a" \
  "$build/tools/NamcoSys147NANDTools/Source/CodeGen/libCodeGen.a" \
  "$build/tools/NamcoSys147NANDTools/Source/Framework/libFramework.a" \
  "$build/tools/NamcoSys147NANDTools/Source/FrameworkHttp/libFramework_Http.a" \
  "$build/tools/NamcoSys147NANDTools/Source/FrameworkAmazon/libFramework_Amazon.a" \
  "$build/tools/NamcoSys147NANDTools/Source/app_shared/libapp_shared.a" \
  "$build/tools/PsfPlayer/Source/unrarsrc-5.2.5/libunrar.a" \
  "$build/tools/NamcoSys147NANDTools/Source/libchdr/libchdr-static.a" \
  "$build/tools/NamcoSys147NANDTools/Source/Framework/zstd_zlibwrapper/liblibzstd_zlibwrapper_static.a" \
  "$build/tools/NamcoSys147NANDTools/Source/Framework/zstd_zlibwrapper/zstd/lib/libzstd.a" \
  "$build/tools/NamcoSys147NANDTools/Source/libchdr/deps/lzma-24.05/liblzma.a" \
  "$build/tools/NamcoSys147NANDTools/Source/xxHash/libxxhash.a"
