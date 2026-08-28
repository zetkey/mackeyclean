#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=dist/MacKeyClean.app
DEST="${1:-$HOME/Applications/MacKeyClean.app}"
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

# Launch the Mach-O directly (not `open`) to dodge the Launch Services re-sign trust race.
"$DEST/Contents/MacOS/MacKeyClean" >/dev/null 2>&1 &
echo "Installed and launched: $DEST"
