#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, and package MouSugu as a DMG,
#              then regenerate the Sparkle appcast that advertises it.
#
# This is the DIRECT channel (Developer ID + notarized DMG + Sparkle).
# For the Mac App Store, use release-appstore.sh — a different target, without
# Sparkle. See APP_STORE.md.
#
# Prerequisites (one-time):
#   1. Apple Developer Program membership (https://developer.apple.com/programs/).
#   2. "Developer ID Application" certificate installed in your Keychain.
#      Xcode → Settings → Accounts → your Apple ID → Manage Certificates → +
#   3. App Store Connect API key in Infisical (engineering/prod):
#      APP_STORE_CONNECT_KEY_ID / _ISSUER_ID / _PRIVATE_KEY — the same key
#      release-appstore.sh uses. notarytool authenticates with it directly.
#   4. Sparkle's Ed25519 signing key in your Keychain (`generate_keys`). The
#      public half is already in Config/Direct-Info.plist as SUPublicEDKey; the
#      private half never leaves the Keychain.
#   5. create-dmg installed:  brew install create-dmg
#
# Usage:
#   ./scripts/release.sh
#
# Output:
#   build/MouSugu-<version>.dmg   — upload this to GitHub Releases
#   website/public/appcast.xml            — commit and publish this

set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

APP_NAME="MouSugu"
APP_DISPLAY="Mou Sugu"
SCHEME="MouSugu"
# The appcast advertises the DMG from GitHub Releases while the feed itself is
# served from mousugu.app — SUFeedURL in Config/Direct-Info.plist points at the feed.
RELEASE_URL_PREFIX="https://github.com/1930-dev/mousugu/releases/download"
PRODUCT_LINK="https://mousugu.app/"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$ROOT_DIR/scripts/ExportOptions.plist"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
APPCAST="$ROOT_DIR/website/public/appcast.xml"

# Sparkle ships its tools inside the SPM artifact, whose path includes a hash.
SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/artifacts/sparkle/Sparkle/bin/generate_appcast" 2>/dev/null | head -1)"
if [[ -z "$SPARKLE_BIN" ]]; then
    echo "✗ Could not find Sparkle's generate_appcast." >&2
    echo "  Build the project once so SwiftPM resolves the Sparkle artifact." >&2
    exit 1
fi
SPARKLE_BIN="$(dirname "$SPARKLE_BIN")"

echo "▸ Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▸ Archiving Release build"
xcodebuild \
    -project "$ROOT_DIR/MouSugu.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    archive

echo "▸ Exporting Developer ID-signed .app"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

# Pull the version out of the built app; used for the appcast URL prefix and
# the GitHub release tag. The DMG filename itself is version-less so the
# website can link to a stable https://.../releases/latest/download/MouSugu.dmg.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

# This channel must ship the updater; the App Store one must not. Catch a
# mis-built archive here rather than shipping an app that can never update.
if [[ ! -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]]; then
    echo "✗ Sparkle.framework is missing from the export — wrong scheme?" >&2
    exit 1
fi

# ---- App Store Connect API key: Infisical -> runtime .p8 ------------------
# Same key and mechanism as release-appstore.sh; nothing sensitive stays on
# disk past the script's lifetime.
INFISICAL_PID="0b3c27f1-21ae-4aa3-b8fb-a21857a6a35f"
secret() { infisical-secret get "$1" --projectId "$INFISICAL_PID" --env prod --plain --silent; }
ASC_KEY_ID="$(secret APP_STORE_CONNECT_KEY_ID)"
ASC_ISSUER_ID="$(secret APP_STORE_CONNECT_ISSUER_ID)"
ASC_KEY_PATH="$(mktemp -t asckey)"
chmod 600 "$ASC_KEY_PATH"
secret APP_STORE_CONNECT_PRIVATE_KEY > "$ASC_KEY_PATH"
trap 'rm -f "$ASC_KEY_PATH"' EXIT

# notarytool only takes zip/pkg/dmg, not a bare .app — ship it a zip and
# staple the app itself afterwards (the DMG below carries the stapled app).
echo "▸ Submitting to Apple's notary service (this can take several minutes)"
NOTARY_ZIP="$BUILD_DIR/$APP_NAME-notary.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
    --key "$ASC_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait
rm "$NOTARY_ZIP"

echo "▸ Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

# --deep is deprecated by Apple for verification and actively discouraged by
# Sparkle, which matters now that we embed a framework with XPC services.
echo "▸ Verifying signature & notarization"
codesign --verify --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "▸ Building DMG"
# Stage a clean folder holding ONLY the app. Handing create-dmg the whole
# export dir dragged its byproducts (DistributionSummary.plist, ExportOptions
# .plist, Packaging.log) into the installer window.
DMG_SRC="$BUILD_DIR/dmg-src"
rm -rf "$DMG_SRC"
mkdir -p "$DMG_SRC"
cp -R "$APP_PATH" "$DMG_SRC/"

# Branded background (scripts/generate_dmg_background.swift) and the app's own
# icon on the mounted volume. Icon positions match the two wells drawn in the
# background art.
DMG_BACKGROUND="$ROOT_DIR/Config/dmg-background@2x.png"
VOL_ICON="$APP_PATH/Contents/Resources/AppIcon.icns"
create-dmg \
    --volname "$APP_DISPLAY" \
    --volicon "$VOL_ICON" \
    --background "$DMG_BACKGROUND" \
    --window-pos 200 120 \
    --window-size 640 400 \
    --icon-size 128 \
    --text-size 13 \
    --icon "$APP_NAME.app" 170 168 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 470 168 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$DMG_SRC"

# generate_appcast signs each archive with the Ed25519 key from the Keychain and
# rewrites the feed in place. It reads every archive in the directory it is
# given, so hand it one holding just this release's DMG.
echo "▸ Regenerating the Sparkle appcast"
FEED_DIR="$BUILD_DIR/appcast"
mkdir -p "$FEED_DIR"
cp "$DMG_PATH" "$FEED_DIR/"
cp "$APPCAST" "$FEED_DIR/appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$RELEASE_URL_PREFIX/v$VERSION/" \
    --link "$PRODUCT_LINK" \
    "$FEED_DIR"
cp "$FEED_DIR/appcast.xml" "$APPCAST"

echo ""
echo "✅ Ready to ship:"
echo "   DMG     $DMG_PATH"
echo "           → gh release create v$VERSION \"$DMG_PATH\" --title \"$APP_DISPLAY $VERSION\""
echo "             (the stable filename keeps .../releases/latest/download/$APP_NAME.dmg working)"
echo "   Appcast $APPCAST"
echo "           → commit, then publish to https://mousugu.app/"
