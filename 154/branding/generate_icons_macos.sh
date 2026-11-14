#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROMIUM_SRC="${CHROMIUM_SRC:-${1:-$(cd "$SCRIPT_DIR/../../.." && pwd)/src}}"
SOURCE="${2:-$SCRIPT_DIR/app_icon.png}"
MAC_DIR="$CHROMIUM_SRC/chrome/app/theme/chromium/mac"

[[ -f "$SOURCE" ]] || { echo "source icon not found: $SOURCE" >&2; exit 1; }
[[ -d "$MAC_DIR" ]] || { echo "macOS theme directory not found: $MAC_DIR" >&2; exit 1; }
command -v sips >/dev/null || { echo "sips is required (run on macOS)" >&2; exit 1; }
command -v iconutil >/dev/null || { echo "iconutil is required (run on macOS)" >&2; exit 1; }

resize() {
  local size="$1"
  local output="$2"
  mkdir -p "$(dirname "$output")"
  sips -z "$size" "$size" "$SOURCE" --out "$output" >/dev/null
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ICONSET="$TMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

resize 16   "$ICONSET/icon_16x16.png"
resize 32   "$ICONSET/icon_16x16@2x.png"
resize 32   "$ICONSET/icon_32x32.png"
resize 64   "$ICONSET/icon_32x32@2x.png"
resize 128  "$ICONSET/icon_128x128.png"
resize 256  "$ICONSET/icon_128x128@2x.png"
resize 256  "$ICONSET/icon_256x256.png"
resize 512  "$ICONSET/icon_256x256@2x.png"
resize 512  "$ICONSET/icon_512x512.png"
resize 1024 "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$MAC_DIR/app.icns"
echo "generated: $MAC_DIR/app.icns"

APPICONSET="$MAC_DIR/Assets.xcassets/AppIcon.appiconset"
for size in 16 32 64 128 256 512 1024; do
  resize "$size" "$APPICONSET/appicon_$size.png"
done
resize 256 "$MAC_DIR/Assets.xcassets/Icon.iconset/icon_256x256.png"
resize 512 "$MAC_DIR/Assets.xcassets/Icon.iconset/icon_256x256@2x.png"
echo "updated: $MAC_DIR/Assets.xcassets"

if command -v xcrun >/dev/null && xcrun --find actool >/dev/null 2>&1; then
  mkdir -p "$TMP_DIR/car"
  if xcrun actool --compile "$TMP_DIR/car" --platform macosx \
       --minimum-deployment-target 10.15 "$MAC_DIR/Assets.xcassets"; then
    cp "$TMP_DIR/car/Assets.car" "$MAC_DIR/Assets.car"
    echo "generated: $MAC_DIR/Assets.car"
  else
    echo "warning: actool failed; Assets.car was not updated" >&2
  fi
else
  echo "warning: actool unavailable; Assets.car was not updated" >&2
fi
