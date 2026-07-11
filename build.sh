#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="CocoaSpice"
CONFIGURATION="${1:-debug}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
LIBGME_SOURCE="/opt/homebrew/lib/libgme.0.dylib"

if [[ ! -f "$LIBGME_SOURCE" ]]; then
  echo "Missing $LIBGME_SOURCE"
  echo "Install it with: brew install game-music-emu"
  exit 1
fi

if [[ ! -x "$ROOT_DIR/scripts/build-libvgm.sh" ]]; then
  chmod +x "$ROOT_DIR/scripts/build-libvgm.sh"
fi
if [[ ! -x "$ROOT_DIR/scripts/build-mgba.sh" ]]; then
  chmod +x "$ROOT_DIR/scripts/build-mgba.sh"
fi
if [[ ! -x "$ROOT_DIR/scripts/build-lazyusf.sh" ]]; then
  chmod +x "$ROOT_DIR/scripts/build-lazyusf.sh"
fi

mkdir -p "$BUILD_DIR" "$DIST_DIR"

xattr -d com.apple.lastuseddate#PS "$ROOT_DIR/app-icon.png" 2>/dev/null || true
xattr -d com.apple.metadata:kMDItemDownloadedDate "$ROOT_DIR/app-icon.png" 2>/dev/null || true
xattr -d com.apple.metadata:kMDItemWhereFroms "$ROOT_DIR/app-icon.png" 2>/dev/null || true
xattr -d com.apple.quarantine "$ROOT_DIR/app-icon.png" 2>/dev/null || true

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/swift-module-cache"

"$ROOT_DIR/scripts/build-libvgm.sh"
"$ROOT_DIR/scripts/build-mgba.sh"
"$ROOT_DIR/scripts/build-lazyusf.sh"

swift build \
  --package-path "$ROOT_DIR" \
  --product "$APP_NAME" \
  --configuration "$CONFIGURATION" \
  --scratch-path "$BUILD_DIR"

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/CocoaSpice-bundle.XXXXXX")"
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

install_name_tool -id "@executable_path/../Frameworks/libgme.0.dylib" "$STAGING_FRAMEWORKS_DIR/libgme.0.dylib"
install_name_tool -change "/opt/homebrew/opt/game-music-emu/lib/libgme.0.dylib" "@executable_path/../Frameworks/libgme.0.dylib" "$STAGING_EXECUTABLE" || true
install_name_tool -change "/opt/homebrew/lib/libgme.0.dylib" "@executable_path/../Frameworks/libgme.0.dylib" "$STAGING_EXECUTABLE" || true

# Finder/File Provider metadata on the bundle will make codesign fail with
# "resource fork, Finder information, or similar detritus not allowed".
# Clear the full bundle recursively after all file copies and install-name edits.
xattr -cr "$STAGING_APP_DIR" 2>/dev/null || true
xattr -c "$STAGING_APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$STAGING_APP_DIR" >/dev/null
xattr -cr "$STAGING_APP_DIR" 2>/dev/null || true
xattr -c "$STAGING_APP_DIR" 2>/dev/null || true
codesign --verify --deep --strict "$STAGING_APP_DIR" >/dev/null

rm -rf "$APP_DIR"
ditto --noextattr --noqtn "$STAGING_APP_DIR" "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true
xattr -c "$APP_DIR" 2>/dev/null || true
codesign --verify --deep --strict "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
