#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source="$root/vendor/highly_theoretical/Core"
build="$root/.build/highly-theoretical"

mkdir -p "$build"
rm -f "$build"/*.o "$build/libhighly_theoretical.a"

clang -std=c11 -O2 \
  -DEMU_COMPILE -DEMU_LITTLE_ENDIAN -DHAVE_STDINT_H -DUSE_M68K -DLSB_FIRST \
  -I"$source" -I"$source/m68k" \
  -c "$source/sega.c" -o "$build/sega.o"
clang -std=c11 -O2 -DEMU_COMPILE -DEMU_LITTLE_ENDIAN -DHAVE_STDINT_H -DUSE_M68K -DLSB_FIRST -I"$source" -I"$source/m68k" -c "$source/dcsound.c" -o "$build/dcsound.o"
clang -std=c11 -O2 -DEMU_COMPILE -DEMU_LITTLE_ENDIAN -DHAVE_STDINT_H -DUSE_M68K -DLSB_FIRST -I"$source" -I"$source/m68k" -c "$source/satsound.c" -o "$build/satsound.o"
clang -std=c11 -O2 -DEMU_COMPILE -DEMU_LITTLE_ENDIAN -DHAVE_STDINT_H -DUSE_M68K -DLSB_FIRST -I"$source" -I"$source/m68k" -c "$source/yam.c" -o "$build/yam.o"
clang -std=c11 -O2 -DEMU_COMPILE -DEMU_LITTLE_ENDIAN -DHAVE_STDINT_H -DUSE_M68K -DLSB_FIRST -I"$source" -I"$source/m68k" -c "$source/arm.c" -o "$build/arm.o"
clang -std=c11 -O2 -DEMU_COMPILE -DEMU_LITTLE_ENDIAN -DHAVE_STDINT_H -DUSE_M68K -DLSB_FIRST -I"$source" -I"$source/m68k" -c "$source/m68k/m68kops.c" -o "$build/m68kops.o"
clang -std=c11 -O2 -DEMU_COMPILE -DEMU_LITTLE_ENDIAN -DHAVE_STDINT_H -DUSE_M68K -DLSB_FIRST -I"$source" -I"$source/m68k" -c "$source/m68k/m68kcpu.c" -o "$build/m68kcpu.o"
libtool -static -o "$build/libhighly_theoretical.a" "$build"/*.o
