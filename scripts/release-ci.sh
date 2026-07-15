#!/usr/bin/env bash
#
# release-ci.sh — headless build/sign/notarize/package for the DIRECT (DMG) channel.
#
# Signs with a "Developer ID Application" .p12 imported into a throwaway keychain
# (cloud signing is NOT available for Developer ID via API key — proven), and
# notarizes with the App Store Connect API key. Designed to run identically on a
# dev Mac (dry-run) and on a GitHub-hosted macOS runner.
#
# Required env (injected from Infisical in CI; export locally for a dry-run):
#   ASC_KEY_ID                App Store Connect API Key ID (10 chars)   [notarization]
#   ASC_ISSUER_ID             Issuer UUID                               [notarization]
#   ASC_PRIVATE_KEY           full contents of AuthKey_XXXX.p8          [notarization]
#   DEVELOPER_ID_CERT_P12     base64 of the Developer ID .p12           [signing]
#   DEVELOPER_ID_CERT_PASSWORD  password for that .p12                  [signing]
#   SPARKLE_ED_KEY            Sparkle Ed25519 private key               [appcast]
#
set -euo pipefail

APP_NAME="MouSugu"
APP_DISPLAY="Mou Sugu"
SCHEME="MouSugu"
TEAM_ID="7RX5GXJ5V3"
SIGN_IDENTITY="Developer ID Application"
RELEASE_URL_PREFIX="https://github.com/1930-dev/mousugu/releases/download"
PRODUCT_LINK="https://mousugu.app/"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
APPCAST="$ROOT_DIR/website/public/appcast.xml"

: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
: "${ASC_PRIVATE_KEY:?set ASC_PRIVATE_KEY}"
: "${DEVELOPER_ID_CERT_P12:?set DEVELOPER_ID_CERT_P12}"
: "${DEVELOPER_ID_CERT_PASSWORD:?set DEVELOPER_ID_CERT_PASSWORD}"

WORK="$(mktemp -d)"
KEYCHAIN="$WORK/mbc-signing.keychain-db"
KC_PASS="$(openssl rand -base64 16)"
ASC_KEY_FILE="$WORK/AuthKey_$ASC_KEY_ID.p8"
SEARCH_RESTORE=""

cleanup() {
    # restore the original keychain search list, then delete the temp keychain
    [[ -n "$SEARCH_RESTORE" ]] && security list-keychains -d user -s $SEARCH_RESTORE >/dev/null 2>&1 || true
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

printf '%s\n' "$ASC_PRIVATE_KEY" > "$ASC_KEY_FILE"

echo "▸ Creating throwaway signing keychain"
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"           # no auto-lock during build
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
# import the .p12 (decode base64 to a temp file first)
P12_FILE="$WORK/developerid.p12"
printf '%s' "$DEVELOPER_ID_CERT_P12" | base64 --decode > "$P12_FILE"
security import "$P12_FILE" -k "$KEYCHAIN" -P "$DEVELOPER_ID_CERT_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/productbuild
# allow codesign to use the key without an interactive prompt (headless)
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null
# prepend our keychain to the search list so xcodebuild/codesign find the identity,
# remembering the original list so we can restore it on exit
SEARCH_RESTORE="$(security list-keychains -d user | sed 's/[\" ]//g' | tr '\n' ' ')"
security list-keychains -d user -s "$KEYCHAIN" $SEARCH_RESTORE

security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$SIGN_IDENTITY" \
    || { echo "✗ Developer ID identity not found in the imported keychain" >&2; exit 1; }
echo "  identity ready: $SIGN_IDENTITY ($TEAM_ID)"

echo "▸ Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

echo "▸ Archiving (Release) signed with Developer ID"
xcodebuild \
    -project "$ROOT_DIR/MouSugu.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN" \
    archive

echo "▸ Exporting Developer ID-signed .app"
EXPORT_OPTS="$WORK/ExportOptions-manual.plist"
cat > "$EXPORT_OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTS"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

# The DMG channel must embed Sparkle; the App Store one must not. Fail fast.
[[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]] || { echo "✗ Sparkle.framework missing from export — wrong scheme?" >&2; exit 1; }

# notarytool only accepts .zip/.pkg/.dmg — zip the .app, notarize, then staple the
# ticket back onto the .app so the copy that lands in the DMG is notarized.
echo "▸ Zipping app for notarization"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "▸ Notarizing (this can take several minutes)"
xcrun notarytool submit "$ZIP_PATH" \
    --key "$ASC_KEY_FILE" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait

echo "▸ Stapling notarization ticket onto the app"
xcrun stapler staple "$APP_PATH"

echo "▸ Verifying signature & notarization"
codesign --verify --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "▸ Building DMG"
create-dmg \
    --volname "$APP_DISPLAY" \
    --window-pos 200 120 \
    --window-size 500 320 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 120 160 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 360 160 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$EXPORT_DIR"

# The DMG is the artifact users download, so it must itself be signed + notarized
# + stapled — otherwise double-clicking the quarantined download is blocked by
# Gatekeeper ("Apple cannot check it"), even though the app inside is notarized.
# Sign first (notarization requires a Developer ID signature + secure timestamp),
# then notarize, then staple — all BEFORE the appcast, since each rewrites the DMG.
echo "▸ Signing the DMG with Developer ID"
codesign --force --timestamp --keychain "$KEYCHAIN" --sign "$SIGN_IDENTITY" "$DMG_PATH"

echo "▸ Notarizing the DMG (this can take several minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --key "$ASC_KEY_FILE" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait
echo "▸ Stapling notarization ticket onto the DMG"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "▸ Regenerating the Sparkle appcast"
# Sparkle ships generate_appcast inside the SPM binary artifact, resolved into
# DerivedData during the archive above (so we look it up here, not before).
SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/artifacts/sparkle/Sparkle/bin/generate_appcast" 2>/dev/null | head -1)"
[[ -n "$SPARKLE_BIN" ]] || { echo "✗ generate_appcast not found after archive." >&2; exit 1; }
SPARKLE_BIN="$(dirname "$SPARKLE_BIN")"
FEED_DIR="$BUILD_DIR/appcast"; mkdir -p "$FEED_DIR"
cp "$DMG_PATH" "$FEED_DIR/"
cp "$APPCAST" "$FEED_DIR/appcast.xml"
GEN_ARGS=(--download-url-prefix "$RELEASE_URL_PREFIX/v$VERSION/" --link "$PRODUCT_LINK")
if [[ -n "${SPARKLE_ED_KEY:-}" ]]; then
    ED_KEY_FILE="$WORK/sparkle_ed_priv"
    printf '%s\n' "$SPARKLE_ED_KEY" > "$ED_KEY_FILE"
    GEN_ARGS+=(--ed-key-file "$ED_KEY_FILE")
fi
"$SPARKLE_BIN/generate_appcast" "${GEN_ARGS[@]}" "$FEED_DIR"
cp "$FEED_DIR/appcast.xml" "$APPCAST"

echo ""
echo "✅ Built and notarized:"
echo "   DMG     $DMG_PATH"
echo "           → upload to $RELEASE_URL_PREFIX/v$VERSION/"
echo "   Appcast $APPCAST"
