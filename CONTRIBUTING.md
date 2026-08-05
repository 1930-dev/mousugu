# Contributing to Mou Sugu

Thanks for your interest in improving Mou Sugu. This guide covers building the
app, the project layout, and how releases are cut. For user-facing information,
see the [README](README.md).

## Prerequisites

- macOS 15 (Sequoia) or later
- Xcode 16 or later (ships the macOS 15 SDK)

## Build from source

```bash
git clone https://github.com/1930-dev/mousugu.git
cd mousugu
open MouSugu.xcodeproj
```

Select the **MouSugu** scheme and **Product → Run**. Xcode resolves the only
dependency — [Sparkle](https://github.com/sparkle-project/Sparkle), via Swift
Package Manager — on the first build. On first launch, grant calendar access
when prompted.

## Project layout

| Path | What |
| --- | --- |
| `MouSugu/` | App sources — SwiftUI `MenuBarExtra`, EventKit |
| `Localizable.xcstrings` | UI strings, localized into English and Spanish |
| `Config/App-Common.xcconfig` | Shared build settings, incl. version and deployment target |
| `scripts/` | Release, icon, and DMG-background tooling |
| `website/` | Astro marketing site and the Sparkle appcast |

## Two build targets

Mou Sugu ships from two schemes over the same sources:

| Channel | Scheme | Updater |
| --- | --- | --- |
| Direct (DMG) | `MouSugu` | Sparkle |
| Mac App Store | `MouSugu-MAS` | Apple's |

Only the direct target links Sparkle — Apple rejects apps that bundle their own
updater, and SPM links per target rather than per configuration.

## Localization

UI strings live in `Localizable.xcstrings` (source English, translated into
Spanish). Add or edit translations in Xcode's string-catalog editor. New
languages are welcome.

## Coding conventions

- Match the surrounding SwiftUI style; keep functions small and
  intention-revealing.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat`, `fix`, `chore`, `docs`, `refactor`, `test`) — imperative, lowercase,
  no trailing period.
- Make sure the app builds cleanly before opening a pull request.

## Cutting a release

Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in
`Config/App-Common.xcconfig`, then run the script for each channel:

- `scripts/release.sh` archives, signs with your Developer ID, notarizes,
  staples, packages a DMG, and regenerates `website/public/appcast.xml` signed
  with the Ed25519 key in your Keychain.
- `scripts/release-appstore.sh` archives the App Store target, refuses to
  proceed if Sparkle made it into the bundle, then validates and optionally
  uploads.

[APP_STORE.md](APP_STORE.md) explains how the two-target split works and what
App Store Connect still needs. See each script's header for one-time
prerequisites.

## The Homebrew cask

Mou Sugu is distributed through our own tap,
[1930-dev/homebrew-tap](https://github.com/1930-dev/homebrew-tap), as
`Casks/mou-sugu.rb`:

```bash
brew install --cask 1930-dev/tap/mou-sugu
```

**Do not bump the cask by hand.** The release workflow does it: after publishing
the GitHub Release it hashes the DMG asset it just uploaded, rewrites `version`
and `sha256` in the cask, and pushes to the tap with a deploy key. A manual bump
races that commit and, worse, invites a wrong checksum.

Two things are worth knowing before touching the cask:

- The DMG is **not** byte-reproducible — the notarization timestamp lives inside
  the signature, so the same commit built twice gives different bytes. The
  `sha256` must come from the published asset, never from a local rebuild.
- `auto_updates true` is deliberate. The app updates itself through Sparkle, so
  the version on disk runs ahead of the cask between releases; without that line
  `brew outdated` reports upgrades that Homebrew must not apply.

Edits to the cask that are *not* a version bump — a new `zap` path, a changed
`depends_on` — go to the tap repository directly, and `brew audit --cask
--online --strict mou-sugu` has to pass.
