#!/bin/bash
# Builds the MediaRemoteAdapter framework used to read Now Playing data
# (including browser media such as YouTube) on macOS 15.4 and later.
# Source: https://github.com/ungive/mediaremote-adapter (BSD 3-Clause).
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../Support/MediaRemoteAdapter" && pwd)"
OUT="$SRC/build/MediaRemoteAdapter.framework"

rm -rf "$OUT"
mkdir -p "$OUT/Versions/A/Headers" "$OUT/Versions/A/Resources"

ARGS=()
for name in env get globals keys now_playing repeat seek send shuffle speed stream test; do
    ARGS+=("$SRC/src/adapter/$name.m")
done
ARGS+=("$SRC/src/private/MediaRemote.m" "$SRC/src/utility/Debounce.m" "$SRC/src/utility/helpers.m")

clang -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 \
    -fobjc-arc -fvisibility=default \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -I"$SRC/include" -I"$SRC/src" \
    -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
    "${ARGS[@]}" \
    -o "$OUT/Versions/A/MediaRemoteAdapter" 2>/dev/null

cp "$SRC/include/MediaRemoteAdapter.h" "$OUT/Versions/A/Headers/"
cp "$SRC/Info.plist" "$OUT/Versions/A/Resources/Info.plist"

ln -sfn A "$OUT/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$OUT/MediaRemoteAdapter"
ln -sfn Versions/Current/Headers "$OUT/Headers"
ln -sfn Versions/Current/Resources "$OUT/Resources"

codesign --force --sign - "$OUT" >/dev/null 2>&1 || true
echo "› Built $OUT"
