# Publishing to the Mac App Store

MenuBarCalendar ships through two channels from this one repo:

| Channel | Target | Scheme | Updater | Script |
| --- | --- | --- | --- | --- |
| Direct (DMG) | `MenuBarCalendar` | `MenuBarCalendar` | Sparkle | `scripts/release.sh` |
| Mac App Store | `MenuBarCalendar-MAS` | `MenuBarCalendar-MAS` | Apple's | `scripts/release-appstore.sh` |

Both build the same sources and produce `MenuBarCalendar.app`. They differ only
in what the target links and what it is allowed to do.

## How the two channels stay apart

Apple rejects apps that bundle their own updater, so the App Store build must
not contain Sparkle. Swift Package Manager links products **per target**, not
per configuration — there is no way to link Sparkle in Release-Direct but not in
Release-AppStore within one target.

So there are two targets. `MenuBarCalendar-MAS` has an empty
`packageProductDependencies`; that, and nothing else, is what keeps Sparkle out.
Both targets share the same synchronized root group, so the sources live in one
place and neither can drift from the other.

Everything Sparkle needs is confined to `Config/App-Direct.xcconfig`:

- `SWIFT_ACTIVE_COMPILATION_CONDITIONS = SPARKLE` — compiles the updater code in
  `UpdateChecker.swift`. It is an explicit flag rather than
  `canImport(Sparkle)` because `canImport` resolves against the framework search
  path, which includes `BUILT_PRODUCTS_DIR` for every target: it would answer
  `true` in the App Store target whenever the direct target had been built
  first, linking a framework that is never embedded and crashing on launch.
- `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` — fetching the appcast.
- `CODE_SIGN_ENTITLEMENTS = Config/Sparkle.entitlements` — the mach-lookup
  exception Sparkle needs to reach its installer from inside the sandbox.
- `INFOPLIST_FILE = Config/Direct-Info.plist` — `SUFeedURL`, `SUPublicEDKey`,
  `SUEnableInstallerLauncherService`.

None of it appears in `Config/App-MAS.xcconfig`. The App Store target needs no
entitlements file at all: the `ENABLE_*` capability settings in
`Config/App-Common.xcconfig` generate the whole set.

`release-appstore.sh` refuses to export if Sparkle turns up in the archive, so a
regression fails locally instead of at review.

## Project state (already done)

- App Sandbox on, with the calendars entitlement, on both targets.
- `LSApplicationCategoryType = public.app-category.productivity`.
- `ITSAppUsesNonExemptEncryption = NO` (skips the export-compliance prompt).
- `LSUIElement = YES` (menu-bar agent, no Dock icon).
- Deployment target macOS 15, `SUPPORTED_PLATFORMS = macosx`.
- `scripts/ExportOptions-appstore.plist` (`method = app-store-connect`).
- Privacy policy written: `website/privacy.html`.

## App Store Connect — one-time setup (needs your Apple account)

1. Register the bundle id `dev.1930.MenuBarCalendar` in the Developer portal
   under team `7RX5GXJ5V3`.
2. Create the app record in App Store Connect (name, primary language, SKU).
3. **Privacy Policy URL** — required because the app accesses Calendar. Publish
   `website/` to <https://agu.uy/MenuBarCalendar/> and use
   <https://agu.uy/MenuBarCalendar/privacy.html>.
4. **App Privacy ("nutrition label")** — declare calendar access; mark data as
   **not collected / not linked to the user**. The App Store build ships without
   the network entitlement, so it cannot transmit anything.
5. Screenshots — 1280×800, 1440×900, 2560×1600 or 2880×1800.
   **Capture against a synthetic calendar, never your own**: screenshots are
   public and the app renders real event titles.
6. Metadata — description, keywords, support URL, age rating, price (free).

## Build & submit

```bash
./scripts/release-appstore.sh            # archive, check for Sparkle, validate
./scripts/release-appstore.sh --upload   # …and send it to App Store Connect
```

Then attach the build to the version in App Store Connect, finish the metadata,
and submit for review. Xcode's `Product → Archive` on the `MenuBarCalendar-MAS`
scheme followed by `Distribute App → App Store Connect` does the same thing by
hand.
