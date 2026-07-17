#!/usr/bin/env bash
#
# release-appstore.sh — archive the Mac App Store build and hand it to Apple.
#
# This is the MAS channel: the MouSugu-MAS target, which never links
# Sparkle. For the direct/DMG channel use release.sh. See APP_STORE.md.
#
# Signing and upload auth are fully automatic via the App Store Connect API
# key stored in Infisical (engineering/prod): APP_STORE_CONNECT_KEY_ID /
# _ISSUER_ID / _PRIVATE_KEY. The .p8 is fetched at runtime into altool's
# search path and removed on exit — nothing sensitive is left on disk.
# xcodebuild uses the same key with -allowProvisioningUpdates to create or
# refresh the Mac App Store provisioning profile and any missing
# distribution/installer certificate, so there is no manual signing setup.
#
# Prerequisites (one-time, done via the App Store Connect API):
#   1. Bundle id dev.1930.MouSugu registered to team 7RX5GXJ5V3.
#   2. App record created in App Store Connect (name, primary language, SKU).
#
# Usage:
#   ./scripts/release-appstore.sh            # build and validate only
#   ./scripts/release-appstore.sh --upload   # build, validate, then upload
#
# Notarization is not part of this flow: Apple notarizes App Store builds
# server-side.

set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

APP_NAME="MouSugu"
SCHEME="MouSugu-MAS"

UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build-appstore"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$ROOT_DIR/scripts/ExportOptions-appstore.plist"

# ---- App Store Connect API key: Infisical -> runtime .p8 ------------------
INFISICAL_PID="0b3c27f1-21ae-4aa3-b8fb-a21857a6a35f"
secret() { infisical-secret get "$1" --projectId "$INFISICAL_PID" --env prod --plain --silent; }

ASC_KEY_ID="$(secret APP_STORE_CONNECT_KEY_ID)"
ASC_ISSUER_ID="$(secret APP_STORE_CONNECT_ISSUER_ID)"

KEY_DIR="$HOME/.appstoreconnect/private_keys"
KEY_PATH="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
mkdir -p "$KEY_DIR"
( umask 077; secret APP_STORE_CONNECT_PRIVATE_KEY > "$KEY_PATH" )
trap 'rm -f "$KEY_PATH"' EXIT

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "▸ Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▸ Archiving Release build ($SCHEME)"
xcodebuild \
    -project "$ROOT_DIR/MouSugu.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    "${AUTH[@]}" \
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
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    "${AUTH[@]}"

PKG_PATH="$(find "$EXPORT_DIR" -name "*.pkg" | head -1)"
if [[ -z "$PKG_PATH" ]]; then
    echo "✗ No .pkg produced by the export." >&2
    exit 1
fi

echo "▸ Validating with App Store Connect"
xcrun altool --validate-app \
    --type macos \
    --file "$PKG_PATH" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"

if [[ "$UPLOAD" == true ]]; then
    echo "▸ Uploading to App Store Connect"
    xcrun altool --upload-app \
        --type macos \
        --file "$PKG_PATH" \
        --apiKey "$ASC_KEY_ID" \
        --apiIssuer "$ASC_ISSUER_ID"
    echo ""
    echo "✅ Uploaded. Attach the build to a version in App Store Connect and submit."
else
    echo ""
    echo "✅ Validated: $PKG_PATH"
    echo "   Re-run with --upload to send it, or drop the .pkg into Transporter."
fi
