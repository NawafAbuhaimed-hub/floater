#!/bin/bash
# Builds a universal Floater.app and wraps it in a DMG for sharing.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Floater.app"
STAGE="build/dmg"
DMG="build/Floater.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"

echo "==> Building universal (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Floater"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Floater"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/icon/Floater.icns "$APP/Contents/Resources/Floater.icns"
mkdir -p "$APP/Contents/Resources/skills"
cp Resources/Skills/*.md "$APP/Contents/Resources/skills/"
cp Resources/icon/Floater.icns "$APP/Contents/Resources/Floater.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
for set_dir in Resources/Sounds/*/; do
    set_name="$(basename "$set_dir")"
    mkdir -p "$APP/Contents/Resources/$set_name"
    cp "$set_dir"*.mp3 "$APP/Contents/Resources/$set_name/"
done

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature verifies"

echo "==> Checking nothing private got bundled"
if grep -rqI "sk-ant" "$APP" 2>/dev/null; then
    echo "    ABORT: an API key is inside the bundle" >&2
    exit 1
fi
echo "    no credentials in the bundle"

echo "==> Building $DMG"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp docs/INSTALL.txt "$STAGE/READ ME FIRST.txt"
hdiutil create -volname "Floater $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
lipo -info "$APP/Contents/MacOS/Floater"
