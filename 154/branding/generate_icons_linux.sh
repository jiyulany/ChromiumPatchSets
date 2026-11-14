#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROMIUM_SRC="${CHROMIUM_SRC:-${1:-$(cd "$SCRIPT_DIR/../../.." && pwd)/src}}"
SOURCE="${2:-$SCRIPT_DIR/app_icon.png}"
THEME_DIR="$CHROMIUM_SRC/chrome/app/theme"

[[ -f "$SOURCE" ]] || { echo "source icon not found: $SOURCE" >&2; exit 1; }
[[ -d "$THEME_DIR/chromium/linux" ]] || { echo "Linux theme directory not found" >&2; exit 1; }

if command -v magick >/dev/null 2>&1; then
  IMAGE_TOOL=(magick)
elif command -v convert >/dev/null 2>&1; then
  IMAGE_TOOL=(convert)
else
  echo "ImageMagick is required: sudo apt install imagemagick" >&2
  exit 1
fi

resize() {
  local size="$1"
  local output="$2"
  mkdir -p "$(dirname "$output")"
  "${IMAGE_TOOL[@]}" "$SOURCE" -resize "${size}x${size}" "$output"
}

for size in 24 48 64 128 256; do
  resize "$size" "$THEME_DIR/chromium/linux/product_logo_$size.png"
done
for size in 16 32; do
  resize "$size" "$THEME_DIR/default_100_percent/chromium/linux/product_logo_$size.png"
done
for size in 16 24 48 64 128 256; do
  resize "$size" "$THEME_DIR/chromium/product_logo_$size.png"
done
resize 32 "$THEME_DIR/chromium/linux/product_logo_32.xpm"

echo "generated Linux icons under: $THEME_DIR/chromium"
echo "generated installer icons under: $THEME_DIR/default_100_percent/chromium/linux"
