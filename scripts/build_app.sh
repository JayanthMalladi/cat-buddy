#!/bin/bash
# Builds "Vrinda's Cat.app" (universal, ad-hoc signed) and zips it into build/VrindasCat.zip.
# Runs on macOS with Xcode or the Swift toolchain installed. No Apple developer account needed.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/CampusCat"

APP="build/Vrinda's Cat.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CampusCat"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp Resources/animations.json Resources/messages.json Resources/reminders.json "$APP/Contents/Resources/"
cp -R Resources/Animations "$APP/Contents/Resources/Animations"

# App icon from one of the happy frames.
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
SRC=Resources/Animations/happy/frame_020.png
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -s format png -z $((size * 2)) $((size * 2)) "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# The commit this was built from; the app compares it with the latest release to update itself.
# Local builds leave it empty and never self-update.
/usr/libexec/PlistBuddy -c "Add :CatBuildCommit string ${GITHUB_SHA:-}" "$APP/Contents/Info.plist"
# Where the app reads messages from (a Google Sheet or Drive share link). It comes from the
# MESSAGES_URL repo secret so the link stays out of the public code; empty means messages.json on GitHub.
/usr/libexec/PlistBuddy -c "Add :CatMessagesURL string ${MESSAGES_URL:-}" "$APP/Contents/Info.plist"

# Ad-hoc signature: free, no certificate. Apple Silicon refuses to run unsigned code at all.
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

ditto -c -k --keepParent "$APP" build/VrindasCat.zip
# Published next to the zip; installed apps compare it with their own commit to find updates.
echo "${GITHUB_SHA:-}" > build/version.txt
echo "Built $(du -h build/VrindasCat.zip | cut -f1) build/VrindasCat.zip"
