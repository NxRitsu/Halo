#!/bin/bash
# Renders the images of the README into docs/images, from the real island views with sample content.
#
# Needs a Mac with a notch, and the Screen Recording permission for the terminal.
# Each scene shows on screen for a few seconds. Quit Halo first.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=build/DerivedData.noindex
APP=$DERIVED/Build/Products/Debug/Halo.app/Contents/MacOS/Halo
OUTPUT=docs/images

xcodegen generate --quiet
xcodebuild build -project Halo.xcodeproj -scheme Halo -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" -quiet

mkdir -p "$OUTPUT"
for scene in player compact battery; do
    LOG=$(mktemp)
    HALO_VISUAL_SCENE=$scene "$APP" -AppleLanguages '(en)' -AppleLocale en_US > "$LOG" &
    PID=$!
    # Leaves time for the views to settle and for the equalizer to start.
    sleep 3
    WINDOW=$(sed -n 's/^window=//p' "$LOG")
    [ -n "$WINDOW" ] || { kill "$PID"; echo "The $scene scene didn't open"; cat "$LOG"; exit 1; }
    screencapture -x -o -l "$WINDOW" "$OUTPUT/$scene.png"
    sips --resampleWidth 1600 "$OUTPUT/$scene.png" > /dev/null
    kill "$PID"
    wait "$PID" 2>/dev/null || true
    rm "$LOG"
done
ls -lh "$OUTPUT"
