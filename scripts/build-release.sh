#!/bin/bash
# Builds a release of Halo into build/artifacts: Halo-<version>.zip and Halo-<version>.dmg.
#
# Usage: scripts/build-release.sh <version> [build number]
#
# Needs xcodegen and create-dmg (brew install xcodegen create-dmg).
# Signed ad hoc by default. Optional environment variables:
#   SELF_SIGNED_IDENTITY Hash of a self-signed code signing certificate in the keychain. macOS
#                        then recognizes each update as the same app, so permissions survive it.
#   SIGN_IDENTITY        Name of a "Developer ID Application" certificate in the keychain.
#                        Takes precedence over SELF_SIGNED_IDENTITY.
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD
#                        Also notarize with Apple. Needs SIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?Usage: build-release.sh <version> [build number]}
# Sparkle compares build numbers, so they must always grow: the commit count does.
BUILD=${2:-$(git rev-list --count HEAD)}
SIGN_IDENTITY=${SIGN_IDENTITY:-}
SELF_SIGNED_IDENTITY=${SELF_SIGNED_IDENTITY:--}
ARTIFACTS=build/artifacts
# Spotlight skips folders ending in .noindex, so build products don't show up as installed apps.
DERIVED=build/release.noindex
APP=$DERIVED/Build/Products/Release/Halo.app

notarize() {
    xcrun notarytool submit "$1" \
        --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" \
        --wait
}

sign() {
    if [ -z "$SIGN_IDENTITY" ]; then
        # No hardened runtime: its library validation rejects embedded frameworks without a team ID.
        codesign --force --timestamp=none --sign "$SELF_SIGNED_IDENTITY" "$@"
    else
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"
    fi
}

rm -rf "$ARTIFACTS"
mkdir -p "$ARTIFACTS"

xcodegen generate --quiet
xcodebuild build \
    -project Halo.xcodeproj \
    -scheme Halo \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    ARCHS=arm64 \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    -quiet

# Sign from the inside out with a single identity, so that the app can load what it embeds.
SPARKLE=$APP/Contents/Frameworks/Sparkle.framework/Versions/B
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/Frameworks/MediaRemoteHelper.framework"
sign --entitlements Halo/Resources/Halo.entitlements "$APP"
codesign --verify --deep --strict "$APP"

if [ -n "${NOTARY_APPLE_ID:-}" ]; then
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARTIFACTS/notarize.zip"
    notarize "$ARTIFACTS/notarize.zip"
    rm "$ARTIFACTS/notarize.zip"
    xcrun stapler staple "$APP"
fi

ZIP=$ARTIFACTS/Halo-$VERSION.zip
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Finder can't be scripted on CI runners: the window layout is then left to its defaults.
LAYOUT=()
[ -z "${CI:-}" ] || LAYOUT=(--skip-jenkins)

STAGING=$(mktemp -d)
ditto "$APP" "$STAGING/Halo.app"
DMG=$ARTIFACTS/Halo-$VERSION.dmg
create-dmg \
    --volname "Halo $VERSION" \
    --window-size 540 360 \
    --icon-size 96 \
    --icon Halo.app 140 170 \
    --app-drop-link 400 170 \
    --hide-extension Halo.app \
    --no-internet-enable \
    "${LAYOUT[@]+"${LAYOUT[@]}"}" \
    "$DMG" "$STAGING"
rm -rf "$STAGING"

if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    if [ -n "${NOTARY_APPLE_ID:-}" ]; then
        notarize "$DMG"
        xcrun stapler staple "$DMG"
    fi
fi

ls -lh "$ARTIFACTS"
