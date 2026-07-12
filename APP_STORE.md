# Publishing to the Mac App Store

The direct-distribution channel (`scripts/release.sh`, Developer ID + notarized
DMG + Sparkle) ships independently. This document covers the **Mac App Store**
path, which needs a different build and some one-time App Store Connect setup.

## Project state (already done)

- App Sandbox ON with the calendars entitlement (`MenuBarCalendar.entitlements`).
- `LSApplicationCategoryType = public.app-category.productivity`.
- `ITSAppUsesNonExemptEncryption = NO` (skips the export-compliance prompt each release).
- `LSUIElement = YES` (menu-bar agent, no Dock icon).
- Deployment target macOS 15, `SUPPORTED_PLATFORMS = macosx`.
- `scripts/ExportOptions-appstore.plist` (`method = app-store-connect`).

## Sparkle must NOT ship in the App Store build

Apple rejects apps that bundle their own updater. `UpdateChecker.swift` is fully
guarded by `#if canImport(Sparkle)`, so the clean way to produce an
App-Store-safe archive is to build **without the Sparkle package**:

1. In Xcode → Project → Package Dependencies, remove **Sparkle** (or check out a
   branch that never added it).
2. `canImport(Sparkle)` becomes false → the "Check for updates…" menu entry and
   all Sparkle code compile out automatically. No code changes needed.
3. Archive from that state. Re-add Sparkle afterwards for the DMG channel.

> Do not hand-edit the project to conditionally link Sparkle per configuration —
> SPM products link to the target for all configs, so the framework would still
> be embedded and rejected. Removing the package is the reliable path.

## App Store Connect — one-time setup (needs your Apple account)

1. Register the Bundle ID `dev.1930.MenuBarCalendar` in the Developer portal.
2. Create the app record in App Store Connect (name, primary language, SKU).
3. **Privacy Policy URL** — required because the app accesses Calendar. Publish
   one and paste the URL.
4. **App Privacy ("nutrition label")** — declare calendar access; mark data as
   **not collected / not linked to the user** (the app talks to no server).
5. Screenshots — capture the menu-bar countdown and the popover (the README
   placeholder is empty).
6. Metadata — description, keywords, support URL, age rating, price (free).

## Build & submit

1. Remove the Sparkle package (see above).
2. In Xcode: `Product → Archive`.
3. `Distribute App → App Store Connect → Upload` (uses automatic signing with a
   Mac App Store provisioning profile), or export with
   `scripts/ExportOptions-appstore.plist` and upload via `xcrun altool` /
   Transporter.
4. In App Store Connect, attach the build to the version, fill remaining
   metadata, and submit for review.
