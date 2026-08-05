#!/usr/bin/env bash
#
# make-dmg.sh — the one place that turns a signed .app into the DMG we ship.
#
# Sourced by scripts/release.sh (manual, from a dev Mac) and scripts/release-ci.sh
# (headless, on a GitHub runner). The block used to be duplicated literally in
# both scripts and silently drifted: the CI copy handed create-dmg the whole
# export directory — so the DMG carried DistributionSummary.plist,
# ExportOptions.plist and Packaging.log — and never learned about the branded
# background. Sourcing one function is what keeps the two channels honest.
#
# Usage:
#   source "$ROOT_DIR/scripts/lib/make-dmg.sh"
#   make_dmg "$APP_PATH" "$DMG_PATH"
#
# The mounted volume ends up holding exactly three entries: the .app, the alias
# to /Applications, and the hidden .background folder create-dmg adds for the art.

# Volume name shown in Finder when the DMG is mounted.
DMG_VOLNAME="Mou Sugu"

# Resolved from this file, not from the caller, so both scripts agree on where
# the background art lives regardless of where they are invoked from.
MAKE_DMG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DMG_BACKGROUND="$MAKE_DMG_ROOT/Config/dmg-background@2x.png"

# make_dmg <app-path> <dmg-path>
make_dmg() {
    local app_path="$1"
    local dmg_path="$2"

    local app_bundle staging_dir vol_icon
    app_bundle="$(basename "$app_path")"
    staging_dir="$(dirname "$dmg_path")/dmg-src"
    vol_icon="$app_path/Contents/Resources/AppIcon.icns"

    [[ -d "$app_path" ]] || { echo "✗ make_dmg: no app at $app_path" >&2; return 1; }
    [[ -f "$DMG_BACKGROUND" ]] || { echo "✗ make_dmg: no background art at $DMG_BACKGROUND" >&2; return 1; }
    [[ -f "$vol_icon" ]] || { echo "✗ make_dmg: no volume icon at $vol_icon" >&2; return 1; }

    # Stage a folder holding ONLY the app. Handing create-dmg a directory that
    # also contains build byproducts drags them into the installer window.
    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"
    cp -R "$app_path" "$staging_dir/"

    # create-dmg refuses to overwrite; a re-run inside the same build dir must work.
    rm -f "$dmg_path"

    # Icon positions match the two wells drawn in the background art, so the
    # window size and icon size are part of the art's contract — do not tune one
    # without regenerating the other (scripts/generate_dmg_background.swift).
    create-dmg \
        --volname "$DMG_VOLNAME" \
        --volicon "$vol_icon" \
        --background "$DMG_BACKGROUND" \
        --window-pos 200 120 \
        --window-size 640 400 \
        --icon-size 128 \
        --text-size 13 \
        --icon "$app_bundle" 170 168 \
        --hide-extension "$app_bundle" \
        --app-drop-link 470 168 \
        --no-internet-enable \
        "$dmg_path" \
        "$staging_dir"
}
