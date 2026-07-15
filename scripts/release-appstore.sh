#!/usr/bin/env bash
#
# release-appstore.sh — archive the Mac App Store build and hand it to Apple.
#
# This is the MAS channel: the MouSugu-MAS target, which never links
# Sparkle. For the direct/DMG channel use release.sh. See APP_STORE.md.
#
# Prerequisites (one-time):
#   1. The bundle id dev.1930.MouSugu registered to the team, and an app
#      record created in App Store Connect.
#   2. An "Apple Distribution" certificate and a Mac App Store provisioning
#      profile — automatic signing fetches both.
#   3. App Store Connect credentials in your Keychain:
#        xcrun notarytool store-credentials "MouSuguASC" \
#            --apple-id "you@example.com" \
#            --team-id "ABCD123456" \
#            --password "abcd-efgh-ijkl-mnop"   # app-specific password
#
# Usage:
#   ./scripts/release-appstore.sh            # build and validate only
#   ./scripts/release-appstore.sh --upload   # build, validate, then upload
#
# Notarization is not part of this flow: Apple notarizes App Store builds
# server-side.

set -euo pipefail

APP_NAME="MouSugu"
SCHEME="MouSugu-MAS"
ASC_PROFILE="MouSuguASC"

UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build-appstore"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$ROOT_DIR/scripts/ExportOptions-appstore.plist"

echo "▸ Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▸ Archiving Release build ($SCHEME)"
xcodebuild \
    -project "$ROOT_DIR/MouSugu.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    archive

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

# The whole reason this target exists. A stray Sparkle would be rejected, so
# fail here rather than after a round trip through App Store Connect.
echo "▸ Checking the archive carries no updater"
if [[ -d "$ARCHIVED_APP/Contents/Frameworks/Sparkle.framework" ]] \
    || otool -L "$ARCHIVED_APP/Contents/MacOS/$APP_NAME" | grep -qi sparkle; then
    echo "✗ Sparkle is present in an App Store build. Apple will reject this." >&2
    echo "  Check that $SCHEME has no Sparkle in packageProductDependencies" >&2
    echo "  and that Config/App-MAS.xcconfig does not define SPARKLE." >&2
    exit 1
fi

echo "▸ Exporting App Store-signed .pkg"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

PKG_PATH="$(find "$EXPORT_DIR" -name "*.pkg" | head -1)"
if [[ -z "$PKG_PATH" ]]; then
    echo "✗ No .pkg produced by the export." >&2
    exit 1
fi

echo "▸ Validating with App Store Connect"
xcrun altool --validate-app \
    --type macos \
    --file "$PKG_PATH" \
    --keychain-profile "$ASC_PROFILE"

if [[ "$UPLOAD" == true ]]; then
    echo "▸ Uploading to App Store Connect"
    xcrun altool --upload-app \
        --type macos \
        --file "$PKG_PATH" \
        --keychain-profile "$ASC_PROFILE"
    echo ""
    echo "✅ Uploaded. Attach the build to a version in App Store Connect and submit."
else
    echo ""
    echo "✅ Validated: $PKG_PATH"
    echo "   Re-run with --upload to send it, or drop the .pkg into Transporter."
fi
