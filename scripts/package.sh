#!/usr/bin/env bash
# Builds a universal Petal.app and zips it into dist/Petal.zip.
# Usage: scripts/package.sh [version]   (default 0.0.0-dev)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0-dev}"
APP=dist/Petal.app

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Petal"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Petal"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Petal</string>
  <key>CFBundleDisplayName</key><string>Petal</string>
  <key>CFBundleIdentifier</key><string>com.daisytechs.petal</string>
  <key>CFBundleExecutable</key><string>Petal</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Daisy Technology. MIT License.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: not notarized, but Apple Silicon refuses to run unsigned code at all.
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" dist/Petal.zip
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Petal")) → dist/Petal.zip"
