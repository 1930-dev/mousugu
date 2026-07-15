<div align="center">

<img src="MouSugu/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" height="128" alt="Mou Sugu icon" />

# Mou Sugu

**Your next meeting, always one glance away.**

*Mou Sugu (もうすぐ) is Japanese for "almost here".*

A tiny, native macOS menu bar app that shows a live countdown to your next event
and lets you jump into the call with a single click.

[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)](https://developer.apple.com/swift/)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)

</div>

---

## Why

System Settings already knows your schedule — your menu bar doesn't. Mou Sugu
puts the one thing you actually care about right where you're looking: **how long
until your next meeting, and the button to join it.** No window to open, no app to
switch to, no tab to hunt for.

## Features

- **Live countdown in the menu bar** — `in 12m: Standup`, `in 2h: 1:1`, or `Now: Design review`. Updates every minute and rolls over to the next event on its own.
- **One-click join** — detects Zoom, Google Meet, Microsoft Teams, and Webex links in the event URL or notes, and surfaces a **Join** button on the next upcoming meeting.
- **Smart join states** — keeps the button around for a 1h grace window after a meeting ends, and switches to **Rejoin** once you're more than 5 minutes into a call.
- **Today at a glance** — a clean popover lists the rest of today's events, color-coded to match each calendar.
- **Pick your calendars** — toggle exactly which calendars feed the bar.
- **Hide busywork** — events you're marked *free* for (focus blocks, tentative holds) are hidden by default.
- **Start at login** — opt in with one toggle, powered by `SMAppService`.
- **Native through and through** — SwiftUI `MenuBarExtra`, translucent Control-Center-style glass, SF Symbols, full light/dark support.
- **Localized** — English and Spanish, following your system language automatically.
- **Private by design** — runs in the App Sandbox, reads your calendar locally, and talks to no server.

## Screenshots

<div align="center">

<!-- Drop popover / menu-bar screenshots here -->
<em>A live countdown in the bar; today's events and a Join button in the popover.</em>

</div>

## Requirements

- macOS 15 (Sequoia) or later
- Calendar access (granted on first launch)

## Install

### Download

Grab the latest `.dmg` from the [Releases](../../releases) page,
open it, and drag **Mou Sugu** to your Applications folder. This build keeps
itself up to date through [Sparkle](https://github.com/sparkle-project/Sparkle).

A Mac App Store build is also published — same app, minus the updater, since the
App Store ships updates itself.

### Build from source

```bash
git clone https://github.com/1930-dev/mousugu.git
cd mousugu
open MouSugu.xcodeproj
```

Then **Product → Run** in Xcode. On first launch, grant calendar access when prompted.

## Usage

1. Launch the app — a calendar icon with your next event appears in the menu bar.
2. Click it to see the rest of today and to join your next call.
3. Open **Preferences…** to choose calendars, hide free time, and enable start-at-login.

## Releasing

Two channels ship from this repo, as two targets over the same sources:

| Channel | Scheme | Updater | Script |
| --- | --- | --- | --- |
| Direct (DMG) | `MouSugu` | Sparkle | `scripts/release.sh` |
| Mac App Store | `MouSugu-MAS` | Apple's | `scripts/release-appstore.sh` |

`release.sh` archives, signs with your Developer ID, notarizes, staples, packages
a DMG, and regenerates `website/appcast.xml` signed with the Ed25519 key in your
Keychain. `release-appstore.sh` archives the App Store target, refuses to proceed
if Sparkle somehow made it into the bundle, then validates and optionally uploads.

Only the direct target links Sparkle — Apple rejects apps that bundle their own
updater, and SPM links per target rather than per configuration.
[APP_STORE.md](APP_STORE.md) explains how the split works and what App Store
Connect still needs. See each script's header for one-time prerequisites.

## Architecture

| File | Responsibility |
| --- | --- |
| [CalendarBarApp.swift](MouSugu/CalendarBarApp.swift) | App entry point, menu bar extra, popover UI, join-button logic |
| [CalendarStore.swift](MouSugu/CalendarStore.swift) | EventKit access, today's events, countdown, meeting-URL detection |
| [SettingsView.swift](MouSugu/SettingsView.swift) | Preferences window — General and Calendars panes |
| [UpdateChecker.swift](UpdateChecker.swift) | Sparkle wrapper, compiled in only for the direct channel |
| [Constants.swift](MouSugu/Constants.swift) | Localized strings catalog |
| [DesignSystem.swift](DesignSystem.swift) | Spacing, radius, and layout tokens |
| [Config/](Config) | Build settings — shared, then per channel |
| [website/](website) | Landing page, privacy policy, and the Sparkle appcast |

## Icon & legal

The app icon is an original design — a charcoal rounded square holding a 5x5 grid of
dots, with today marked in red — that follows the macOS visual language using
geometry and shadows consistent with Apple's design guidelines. It does **not**
reproduce any copyrighted asset or trademark of Apple Inc. It is rendered from
[scripts/generate_icon.swift](scripts/generate_icon.swift); run that and re-export
the sizes in `AppIcon.appiconset` to change it. The glyphs in the app's interface
come from **SF Symbols**, licensed by Apple for use within its ecosystem.

Apple, macOS, and the Calendar icon are trademarks of Apple Inc., registered in the
U.S. and other countries.

## License

MIT — see [LICENSE](LICENSE).
