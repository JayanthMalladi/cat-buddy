#!/bin/bash
# Builds CampusCat.app (universal, ad-hoc signed) and zips it into build/CampusCat.zip.
# Runs on macOS with Xcode or the Swift toolchain installed. No Apple developer account needed.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/CampusCat"

APP=build/CampusCat.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CampusCat"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp Resources/animations.json Resources/messages.json "$APP/Contents/Resources/"
cp -R Resources/Animations "$APP/Contents/Resources/Animations"

# App icon from one of the awake frames.
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
SRC=Resources/Animations/awake/frame_047.png
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -s format png -z $((size * 2)) $((size * 2)) "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: free, no certificate. Apple Silicon refuses to run unsigned code at all.
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

ditto -c -k --keepParent "$APP" build/CampusCat.zip
echo "Built $(du -h build/CampusCat.zip | cut -f1) build/CampusCat.zip"
