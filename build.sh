#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="CocoaSpice"
CONFIGURATION="${1:-debug}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
# Use the certificate fingerprint, not its display name: this keychain has
# older certificates with the same display name, which makes codesign reject
# a name-only identity as ambiguous.
DEVELOPMENT_SIGNING_IDENTITY="${COCOASPICE_SIGNING_IDENTITY:-1D46142A0CE920B12207A97C60E9DD3C389E4144}"
LIBGME_SOURCE="/opt/homebrew/lib/libgme.0.dylib"
OPENMPT_SOURCE="/opt/homebrew/opt/libopenmpt/lib/libopenmpt.0.dylib"
MPG123_SOURCE="/opt/homebrew/opt/mpg123/lib/libmpg123.0.dylib"
OGG_SOURCE="/opt/homebrew/opt/libogg/lib/libogg.0.dylib"
VORBIS_SOURCE="/opt/homebrew/opt/libvorbis/lib/libvorbis.0.dylib"
VORBISFILE_SOURCE="/opt/homebrew/opt/libvorbis/lib/libvorbisfile.3.dylib"
SIDPLAYFP_SOURCE="/opt/homebrew/opt/libsidplayfp/lib/libsidplayfp.7.dylib"
FFMPEG_SOURCES=(
  "/opt/homebrew/opt/ffmpeg/lib/libavcodec.dylib"
  "/opt/homebrew/opt/ffmpeg/lib/libavformat.dylib"
  "/opt/homebrew/opt/ffmpeg/lib/libavutil.dylib"
  "/opt/homebrew/opt/ffmpeg/lib/libswresample.dylib"
)

if [[ ! -f "$LIBGME_SOURCE" ]]; then
  echo "Missing $LIBGME_SOURCE"
  echo "Install it with: brew install game-music-emu"
  exit 1
fi
for runtime_library in "$OPENMPT_SOURCE" "$MPG123_SOURCE" "$OGG_SOURCE" "$VORBIS_SOURCE" "$VORBISFILE_SOURCE" "$SIDPLAYFP_SOURCE"; do
  if [[ ! -f "$runtime_library" ]]; then
    echo "Missing $runtime_library"
    echo "Install it with: brew install libopenmpt"
    exit 1
  fi
done
for runtime_library in "${FFMPEG_SOURCES[@]}"; do
  if [[ ! -f "$runtime_library" ]]; then
    echo "Missing $runtime_library"
    echo "Install it with: brew install ffmpeg"
    exit 1
  fi
done

mkdir -p "$BUILD_DIR" "$DIST_DIR" "$BUILD_DIR/clang-module-cache" "$BUILD_DIR/swift-module-cache"

xattr -d com.apple.lastuseddate#PS "$ROOT_DIR/app-icon.png" 2>/dev/null || true
xattr -d com.apple.metadata:kMDItemDownloadedDate "$ROOT_DIR/app-icon.png" 2>/dev/null || true
xattr -d com.apple.metadata:kMDItemWhereFroms "$ROOT_DIR/app-icon.png" 2>/dev/null || true
xattr -d com.apple.quarantine "$ROOT_DIR/app-icon.png" 2>/dev/null || true

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/swift-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/swift-module-cache"

VGMBoy_DIR="$ROOT_DIR/../VGMBoy"
"$VGMBoy_DIR/scripts/build-dependencies.sh"

swift build \
  --package-path "$ROOT_DIR" \
  --product "$APP_NAME" \
  --configuration "$CONFIGURATION" \
  --disable-sandbox \
  --scratch-path "$BUILD_DIR"

STAGING_ROOT="$(mktemp -d "/private/tmp/CocoaSpice-bundle.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT

STAGING_APP_DIR="$STAGING_ROOT/$APP_NAME.app"
STAGING_CONTENTS="$STAGING_APP_DIR/Contents"
STAGING_EXECUTABLE="$STAGING_CONTENTS/MacOS/$APP_NAME"
STAGING_FRAMEWORKS_DIR="$STAGING_CONTENTS/Frameworks"

mkdir -p "$STAGING_CONTENTS/MacOS" "$STAGING_FRAMEWORKS_DIR" "$STAGING_CONTENTS/Resources"

cp -X "$ROOT_DIR/Resources/Info.plist" "$STAGING_CONTENTS/Info.plist"
if [[ -f "$ROOT_DIR/app-icon.png" ]]; then
  cp -X "$ROOT_DIR/app-icon.png" "$STAGING_CONTENTS/Resources/AppIcon.png"
  xattr -c "$STAGING_CONTENTS/Resources/AppIcon.png" || true
fi
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp -X "$ROOT_DIR/Resources/AppIcon.icns" "$STAGING_CONTENTS/Resources/AppIcon.icns"
  xattr -c "$STAGING_CONTENTS/Resources/AppIcon.icns" || true
fi
cp -X "$BUILD_DIR/$CONFIGURATION/$APP_NAME" "$STAGING_EXECUTABLE"
cp -X "$LIBGME_SOURCE" "$STAGING_FRAMEWORKS_DIR/libgme.0.dylib"
cp -X "$OPENMPT_SOURCE" "$STAGING_FRAMEWORKS_DIR/libopenmpt.0.dylib"
ditto --noextattr --noqtn "$MPG123_SOURCE" "$STAGING_FRAMEWORKS_DIR/libmpg123.0.dylib"
cp -X "$OGG_SOURCE" "$STAGING_FRAMEWORKS_DIR/libogg.0.dylib"
cp -X "$VORBIS_SOURCE" "$STAGING_FRAMEWORKS_DIR/libvorbis.0.dylib"
cp -X "$VORBISFILE_SOURCE" "$STAGING_FRAMEWORKS_DIR/libvorbisfile.3.dylib"
cp -X "$SIDPLAYFP_SOURCE" "$STAGING_FRAMEWORKS_DIR/libsidplayfp.7.dylib"

# vgmstream uses FFmpeg for ATRAC3/MSF decoding. Copy the four directly linked
# FFmpeg dylibs and every Homebrew dylib they depend on, then retarget all
# bundled edges below so the completed app has no Homebrew runtime requirement.
bundled_runtime_basenames=()
bundled_runtime_sources=()
has_bundled_runtime_library() {
  local candidate="$1"
  local existing
  for existing in "${bundled_runtime_basenames[@]:-}"; do
    if [[ "$existing" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}
bundle_runtime_library() {
  local source="$1"
  local basename
  basename="$(otool -D "$source" | tail -n 1 | xargs basename)"
  if has_bundled_runtime_library "$basename"; then
    return
  fi
  bundled_runtime_basenames+=("$basename")
  bundled_runtime_sources+=("$source")
  if [[ -e "$STAGING_FRAMEWORKS_DIR/$basename" ]]; then
    return
  fi
  cp -X "$source" "$STAGING_FRAMEWORKS_DIR/$basename"

  local dependency
  while IFS= read -r dependency; do
    if [[ "$dependency" == /opt/homebrew/* && -f "$dependency" ]]; then
      bundle_runtime_library "$dependency"
    fi
  done < <(otool -L "$source" | tail -n +2 | awk '{ print $1 }')
}
for runtime_library in "${FFMPEG_SOURCES[@]}"; do
  bundle_runtime_library "$runtime_library"
done

install_name_tool -id "@executable_path/../Frameworks/libgme.0.dylib" "$STAGING_FRAMEWORKS_DIR/libgme.0.dylib"
for runtime_library in libopenmpt.0.dylib libmpg123.0.dylib libogg.0.dylib libvorbis.0.dylib libvorbisfile.3.dylib libsidplayfp.7.dylib; do
  install_name_tool -id "@executable_path/../Frameworks/$runtime_library" "$STAGING_FRAMEWORKS_DIR/$runtime_library"
done
install_name_tool -change "/opt/homebrew/opt/game-music-emu/lib/libgme.0.dylib" "@executable_path/../Frameworks/libgme.0.dylib" "$STAGING_EXECUTABLE" || true
install_name_tool -change "/opt/homebrew/lib/libgme.0.dylib" "@executable_path/../Frameworks/libgme.0.dylib" "$STAGING_EXECUTABLE" || true
install_name_tool -change "/opt/homebrew/opt/libopenmpt/lib/libopenmpt.0.dylib" "@executable_path/../Frameworks/libopenmpt.0.dylib" "$STAGING_EXECUTABLE"
install_name_tool -change "$OGG_SOURCE" "@executable_path/../Frameworks/libogg.0.dylib" "$STAGING_EXECUTABLE" || true
install_name_tool -change "$VORBIS_SOURCE" "@executable_path/../Frameworks/libvorbis.0.dylib" "$STAGING_EXECUTABLE" || true
install_name_tool -change "$VORBISFILE_SOURCE" "@executable_path/../Frameworks/libvorbisfile.3.dylib" "$STAGING_EXECUTABLE" || true
install_name_tool -change "$SIDPLAYFP_SOURCE" "@executable_path/../Frameworks/libsidplayfp.7.dylib" "$STAGING_EXECUTABLE" || true
install_name_tool -change "/opt/homebrew/opt/mpg123/lib/libmpg123.0.dylib" "@executable_path/../Frameworks/libmpg123.0.dylib" "$STAGING_FRAMEWORKS_DIR/libopenmpt.0.dylib"
install_name_tool -change "/opt/homebrew/opt/libogg/lib/libogg.0.dylib" "@executable_path/../Frameworks/libogg.0.dylib" "$STAGING_FRAMEWORKS_DIR/libopenmpt.0.dylib"
install_name_tool -change "/opt/homebrew/opt/libvorbis/lib/libvorbis.0.dylib" "@executable_path/../Frameworks/libvorbis.0.dylib" "$STAGING_FRAMEWORKS_DIR/libopenmpt.0.dylib"
install_name_tool -change "/opt/homebrew/opt/libvorbis/lib/libvorbisfile.3.dylib" "@executable_path/../Frameworks/libvorbisfile.3.dylib" "$STAGING_FRAMEWORKS_DIR/libopenmpt.0.dylib"
install_name_tool -change "/opt/homebrew/opt/libogg/lib/libogg.0.dylib" "@executable_path/../Frameworks/libogg.0.dylib" "$STAGING_FRAMEWORKS_DIR/libvorbis.0.dylib"
install_name_tool -change "/opt/homebrew/Cellar/libvorbis/1.3.7/lib/libvorbis.0.dylib" "@executable_path/../Frameworks/libvorbis.0.dylib" "$STAGING_FRAMEWORKS_DIR/libvorbisfile.3.dylib"
install_name_tool -change "/opt/homebrew/opt/libogg/lib/libogg.0.dylib" "@executable_path/../Frameworks/libogg.0.dylib" "$STAGING_FRAMEWORKS_DIR/libvorbisfile.3.dylib"

for runtime_index in "${!bundled_runtime_basenames[@]}"; do
  runtime_basename="${bundled_runtime_basenames[$runtime_index]}"
  runtime_source="${bundled_runtime_sources[$runtime_index]}"
  runtime_destination="$STAGING_FRAMEWORKS_DIR/$runtime_basename"
  install_name_tool -id "@executable_path/../Frameworks/$runtime_basename" "$runtime_destination"
  while IFS= read -r dependency; do
    dependency_basename="$(basename "$dependency")"
    if has_bundled_runtime_library "$dependency_basename"; then
      install_name_tool -change "$dependency" "@executable_path/../Frameworks/$dependency_basename" "$runtime_destination"
    fi
  done < <(otool -L "$runtime_source" | tail -n +2 | awk '{ print $1 }')
  install_name_tool -change "$runtime_source" "@executable_path/../Frameworks/$runtime_basename" "$STAGING_EXECUTABLE" || true
  runtime_install_name="$(otool -D "$runtime_source" | tail -n 1)"
  install_name_tool -change "$runtime_install_name" "@executable_path/../Frameworks/$runtime_basename" "$STAGING_EXECUTABLE" || true
done

# Finder/File Provider metadata on the bundle will make codesign fail with
# "resource fork, Finder information, or similar detritus not allowed".
# Clear the full bundle recursively after all file copies and install-name edits.
xattr -cr "$STAGING_APP_DIR" 2>/dev/null || true
xattr -c "$STAGING_APP_DIR" 2>/dev/null || true
if security find-identity -v -p codesigning | grep -Fq "$DEVELOPMENT_SIGNING_IDENTITY"; then
  SIGNING_IDENTITY="$DEVELOPMENT_SIGNING_IDENTITY"
else
  # Keep the script usable on another developer's machine, but an ad-hoc
  # signature does not retain macOS permission identity between rebuilds.
  SIGNING_IDENTITY="-"
  echo "No configured development signing identity; using ad-hoc signing."
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" "$STAGING_APP_DIR" >/dev/null
xattr -cr "$STAGING_APP_DIR" 2>/dev/null || true
xattr -c "$STAGING_APP_DIR" 2>/dev/null || true
codesign --verify --deep --strict "$STAGING_APP_DIR" >/dev/null

rm -rf "$APP_DIR"
ditto --noextattr --noqtn "$STAGING_APP_DIR" "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true
xattr -c "$APP_DIR" 2>/dev/null || true
codesign --verify --deep --strict "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
