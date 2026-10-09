#!/usr/bin/env bash
# Builds Resources/AppIcon.icns from a source image.
#
#   ./scripts/make_icon.sh ~/Downloads/logo.png [output.icns]
#
# Pipeline:
#   1. If the source still has a background, scripts/matte.swift cuts it out, keeping
#      soft edges and the neutral shadow as real alpha. An already-transparent source
#      (PNG with transparent corners) skips this step.
#   2. scripts/iconify.swift trims the artwork, scales it to fit the icon canvas
#      without cropping, propagates the nearest edge colour into the remaining canvas
#      so gradients continue into the corners, and masks the result to the macOS icon
#      shape (squircle).
#   3. Every icon size is rendered and packed into the .icns.
#
# Step 2's mask is not cosmetic: macOS only draws an app icon as-is when its opaque
# silhouette is the system icon shape. Any other silhouette is composited onto the
# system's own light plate, which looks like a white background behind the logo.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:?usage: make_icon.sh <source-image> [output.icns]}"
OUT="${2:-Resources/AppIcon.icns}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MASTER=1024
RADIUS_RATIO=0.2237   # macOS icon corner radius as a fraction of the icon size

[ -f "$SRC" ] || { echo "no such file: $SRC" >&2; exit 1; }

echo "== source $(basename "$SRC")  $(magick identify -format '%wx%h %[channels]' "$SRC")"

# A source with transparent corners already has its background removed.
CORNERS="$(magick "$SRC" -format '%[fx:p{2,2}.a],%[fx:p{w-3,2}.a],%[fx:p{2,h-3}.a],%[fx:p{w-3,h-3}.a]' info:)"
ALPHA_MEAN="$(magick "$SRC" -alpha extract -format '%[fx:mean]' info:)"
TRANSPARENT="$(python3 -c "
corners = [float(v) for v in '$CORNERS'.split(',')]
print('yes' if max(corners) < 0.05 and $ALPHA_MEAN < 0.995 else 'no')")"

if [ "$TRANSPARENT" = "yes" ]; then
  echo "== background already transparent (corners alpha=$CORNERS) — skipping matte"
  cp "$SRC" "$WORK/artwork.png"
else
  echo "== matting (corners alpha=$CORNERS)"
  swiftc -O -swift-version 5 scripts/matte.swift -o "$WORK/matte"
  "$WORK/matte" "$SRC" "$WORK/artwork.rgba"
  magick -size "$(magick identify -format '%wx%h' "$SRC")" -depth 8 rgba:"$WORK/artwork.rgba" \
    -define png:color-type=6 "$WORK/artwork.png"
fi

echo "== composing the ${MASTER}px icon master"
swiftc -O -swift-version 5 scripts/iconify.swift -o "$WORK/iconify"
"$WORK/iconify" "$WORK/artwork.png" "$WORK/master.rgba" "$MASTER" "$RADIUS_RATIO"
magick -size "${MASTER}x${MASTER}" -depth 8 rgba:"$WORK/master.rgba" -define png:color-type=6 \
  "$WORK/master.png"

echo "== rendering icon sizes"
rm -rf "$WORK/AppIcon.iconset"
mkdir -p "$WORK/AppIcon.iconset"
emit() { # emit <size> <filename>
  magick "$WORK/master.png" -filter Lanczos -resize "$1x$1" "$WORK/AppIcon.iconset/$2"
}
emit 16   icon_16x16.png
emit 32   icon_16x16@2x.png
emit 32   icon_32x32.png
emit 64   icon_32x32@2x.png
emit 128  icon_128x128.png
emit 256  icon_128x128@2x.png
emit 256  icon_256x256.png
emit 512  icon_256x256@2x.png
emit 512  icon_512x512.png
emit 1024 icon_512x512@2x.png

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$OUT"

echo "== wrote $OUT"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUT" | tail -3
