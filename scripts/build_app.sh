#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/MacKeyClean.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/MacKeyClean "$APP/Contents/MacOS/MacKeyClean"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.mackeyclean.app</string>
  <key>CFBundleName</key><string>MacKeyClean</string>
  <key>CFBundleDisplayName</key><string>KeyClean</string>
  <key>CFBundleExecutable</key><string>MacKeyClean</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built: $(cd dist && pwd)/MacKeyClean.app"
