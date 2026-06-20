#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, and package MenuBarCalendar as a DMG.
#
# Prerequisites (one-time):
#   1. Apple Developer Program membership (https://developer.apple.com/programs/).
#   2. "Developer ID Application" certificate installed in your Keychain.
#      Xcode → Settings → Accounts → your Apple ID → Manage Certificates → +
#   3. Project signing in Xcode: set "Signing & Capabilities" → Team to your
#      developer team (Automatic signing on).
#   4. App-specific password for notarization, saved in Keychain via:
#        xcrun notarytool store-credentials "MenuBarCalendarNotary" \
#            --apple-id "you@example.com" \
#            --team-id "ABCD123456" \
#            --password "abcd-efgh-ijkl-mnop"   # app-specific password
#   5. create-dmg installed:  brew install create-dmg
#
# Usage:
#   ./scripts/release.sh
#
# Output:
#   build/MenuBarCalendar-<version>.dmg

set -euo pipefail

APP_NAME="MenuBarCalendar"
SCHEME="MenuBarCalendar"
NOTARY_PROFILE="MenuBarCalendarNotary"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$ROOT_DIR/scripts/ExportOptions.plist"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"

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

echo "▸ Submitting to Apple's notary service (this can take several minutes)"
xcrun notarytool submit "$APP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "▸ Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

echo "▸ Verifying signature & notarization"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
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

echo ""
echo "✅ Ready to ship: $DMG_PATH"
