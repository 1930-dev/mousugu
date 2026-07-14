#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, and package MenuBarCalendar as a DMG,
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
#   3. App-specific password for notarization, saved in Keychain via:
#        xcrun notarytool store-credentials "MenuBarCalendarNotary" \
#            --apple-id "you@example.com" \
#            --team-id "ABCD123456" \
#            --password "abcd-efgh-ijkl-mnop"   # app-specific password
#   4. Sparkle's Ed25519 signing key in your Keychain (`generate_keys`). The
#      public half is already in Config/Direct-Info.plist as SUPublicEDKey; the
#      private half never leaves the Keychain.
#   5. create-dmg installed:  brew install create-dmg
#
# Usage:
#   ./scripts/release.sh
#
# Output:
#   build/MenuBarCalendar-<version>.dmg   — upload this to GitHub Releases
#   website/appcast.xml                   — commit and publish this

set -euo pipefail

APP_NAME="MenuBarCalendar"
SCHEME="MenuBarCalendar"
NOTARY_PROFILE="MenuBarCalendarNotary"
# The appcast advertises the DMG from GitHub Releases while the feed itself is
# served from agu.uy — SUFeedURL in Config/Direct-Info.plist points at the feed.
RELEASE_URL_PREFIX="https://github.com/1930-dev/MenuBarCalendar/releases/download"
PRODUCT_LINK="https://agu.uy/MenuBarCalendar/"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$ROOT_DIR/scripts/ExportOptions.plist"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
APPCAST="$ROOT_DIR/website/appcast.xml"

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
    -project "$ROOT_DIR/MenuBarCalendar.xcodeproj" \
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

# Pull the version out of the built app so the DMG carries the same string.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

# This channel must ship the updater; the App Store one must not. Catch a
# mis-built archive here rather than shipping an app that can never update.
if [[ ! -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]]; then
    echo "✗ Sparkle.framework is missing from the export — wrong scheme?" >&2
    exit 1
fi

echo "▸ Submitting to Apple's notary service (this can take several minutes)"
xcrun notarytool submit "$APP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "▸ Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

# --deep is deprecated by Apple for verification and actively discouraged by
# Sparkle, which matters now that we embed a framework with XPC services.
echo "▸ Verifying signature & notarization"
codesign --verify --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "▸ Building DMG"
create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 500 320 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 120 160 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 360 160 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$EXPORT_DIR"

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
echo "           → upload to $RELEASE_URL_PREFIX/v$VERSION/"
echo "   Appcast $APPCAST"
echo "           → commit, then publish to https://agu.uy/MenuBarCalendar/"
