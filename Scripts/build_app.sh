#!/bin/bash
# Build Nook.app from the Swift package and ad-hoc sign it.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD="$ROOT/.build/release"
APP="$ROOT/Nook.app"

echo "› Compiling (release)"
swift build -c release --arch arm64

echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/Nook" "$APP/Contents/MacOS/Nook"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f "$ROOT/Support/AppIcon.icns" ]; then
  cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "› MediaRemote adapter"
"$ROOT/Scripts/build_mediaremote.sh" >/dev/null
cp "$ROOT/Support/MediaRemoteAdapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
rm -rf "$APP/Contents/Resources/MediaRemoteAdapter.framework"
cp -R "$ROOT/Support/MediaRemoteAdapter/build/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"

echo "› Ad-hoc signing"
codesign --force --options runtime --timestamp=none --sign - "$APP/Contents/MacOS/Nook" >/dev/null 2>&1 || \
  codesign --force --sign - "$APP/Contents/MacOS/Nook"
codesign --force --sign - "$APP"

echo "› Built $APP"
echo "  open it with:  open \"$APP\""
