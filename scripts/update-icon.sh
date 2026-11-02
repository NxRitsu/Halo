#!/bin/bash
# Regenerates the app icon in the asset catalog from scripts/generate-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET=Halo/Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p "$ICONSET"

MASTER="$(mktemp -d)/icon.png"
swift -target arm64-apple-macos26.0 scripts/generate-icon.swift "$MASTER"

IMAGES=""
for POINTS in 16 32 128 256 512; do
    for SCALE in 1 2; do
        PIXELS=$((POINTS * SCALE))
        NAME="icon_${POINTS}x${POINTS}@${SCALE}x.png"
        sips --setProperty format png --resampleWidth "$PIXELS" "$MASTER" --out "$ICONSET/$NAME" >/dev/null
        IMAGES+="${IMAGES:+,$'\n'}    { \"filename\" : \"$NAME\", \"idiom\" : \"mac\", \"scale\" : \"${SCALE}x\", \"size\" : \"${POINTS}x${POINTS}\" }"
    done
done

cat > "$ICONSET/Contents.json" <<EOF
{
  "images" : [
$IMAGES
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

cat > Halo/Resources/Assets.xcassets/Contents.json <<EOF
{
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
