#!/bin/bash
# Builds Floater.app into ./build and (optionally) installs it to ~/Applications.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${CONFIG:-release}"
APP="build/Floater.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Floater"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Floater"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/icon/Floater.icns "$APP/Contents/Resources/Floater.icns"
# Each sound set keeps its own subdirectory inside the bundle.
for set_dir in Resources/Sounds/*/; do
    set_name="$(basename "$set_dir")"
    mkdir -p "$APP/Contents/Resources/$set_name"
    cp "$set_dir"*.mp3 "$APP/Contents/Resources/$set_name/" 2>/dev/null || true
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Floater.app"
    cp -R "$APP" "$HOME/Applications/Floater.app"
    echo "==> Installed to ~/Applications/Floater.app"
fi

echo "==> Done: $APP"
