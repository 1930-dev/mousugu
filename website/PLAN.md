# Mou Sugu marketing site — SEO-first plan

Reference competitor: [Dot](https://www.trydot.app) (analyzed 2026-07-15 via local
mirror). Same niche, strong SEO execution. This plan matches their strengths and
exploits their gaps.

## What Dot does (and what we copy or beat)

| Practice | Dot | Mou Sugu plan |
| --- | --- | --- |
| Keyword-first title | `Dot — Menu Bar Calendar for Mac with Meeting Reminders` | Same pattern, our keywords |
| Meta description / OG / Twitter cards | Complete, og-image 1208×638 | Complete, designed og-image 1200×630 |
| JSON-LD | `SoftwareApplication` + `Offer` | Same **plus `FAQPage`** (they lack it) |
| Long-form single landing | Hero → press → features → personas → FAQ | Same skeleton, original copy |
| Changelog page | Freshness signal | Ship it, regenerate per release |
| Canonical | Broken (`href="index.html"`) | Absolute URLs |
| Comparison pages | None | `/vs/` pages — their biggest gap |
| Localization | English only | EN + ES with hreflang (app is already bilingual) |

## Keyword strategy

Validate volumes in the Ahrefs UI before writing copy (API access is
plan-gated; numbers below are unvalidated priors from Dot's own targeting).

- **Primary (landing):** `menu bar calendar mac`, `mac menu bar calendar`,
  `menu bar calendar`, `calendar in menu bar`
- **Secondary (landing H2s):** `meeting countdown mac`, `next meeting in menu
  bar`, `join zoom meetings from menu bar`, `join google meet one click mac`,
  `join teams meeting mac menu bar`
- **Bottom-funnel (dedicated pages):** `itsycal alternative`, `meetingbar
  alternative`, `dato app alternative`, `best menu bar calendar for mac`
- **Long-tail (FAQ + blog):** `how to see calendar in mac menu bar`, `how to
  join zoom meetings faster on mac`, `show next meeting in menu bar macos`,
  `menu bar calendar with countdown`
- **Brand:** `mou sugu`, `mousugu app`, `もうすぐ app`

Positioning wedge vs Dot ($15, closed): **free, open source, private by
design, App Sandbox** — also the Show HN / Product Hunt angle.

## Site architecture

One URL = one search intent. Do not fragment before there is traffic.

```
/                     landing — primary keywords (EN)
/es/                  landing in Spanish — hreflang pair
/changelog            freshness + feature keywords, updated per release
/privacy              exists; keep
/vs/itsycal           phase 2 — comparison pages
/vs/meetingbar        phase 2
/vs/dato              phase 2
/blog/<slug>          phase 3 — how-to guides feeding long-tail
sitemap.xml, robots.txt, og-image.png, favicon set
```

## On-page rules (every page)

- `<title>` ≤ 60 chars, keyword first, brand last: `Mou Sugu — Menu Bar
  Calendar for Mac with Meeting Countdown`.
- Meta description 150–160 chars, includes primary keyword + CTA.
- Exactly one `<h1>`, benefit + keyword. H2s carry secondary keywords.
- Absolute `rel=canonical`; `hreflang` en/es/x-default pairs.
- Full OG + Twitter card; `summary_large_image`.
- JSON-LD: `SoftwareApplication` (operatingSystem macOS, price 0,
  `aggregateRating` once MAS reviews exist) + `FAQPage` on the landing +
  `BreadcrumbList` on internal pages.
- Every screenshot has a descriptive, keyword-bearing `alt`.
- All internal pages linked from the footer (crawl depth 1).

## Technical stack

- **Astro** (static output) — components let `/vs/` and blog pages scale
  without abandoning plain HTML output; zero client JS by default keeps Core
  Web Vitals green. Current hand-written HTML migrates in.
- **Cloudflare Pages** on `mousugu.app` (free, global CDN, automatic HTTPS —
  `.app` is HSTS-preloaded so HTTPS is mandatory anyway). The Sparkle appcast
  ships from the same deploy (`/appcast.xml`, already the SUFeedURL).
- Performance budget: LCP < 2.5 s, total page < 300 KB, images AVIF/WebP with
  explicit dimensions, system font stack or one subset woff2.
- Design language: sumi black + shu red + liquid glass (the hinomaru icon
  story) — distinct from Dot's look, consistent with the app.

## Distribution (nothing ranks without links)

1. Listings: macmenubar.com, MacUpdate, AlternativeTo (file as alternative to
   Itsycal / MeetingBar / Dato / Dot), awesome-mac and awesome-menubar GitHub
   lists (PRs).
2. Launches: Show HN (open-source angle), Product Hunt, r/macapps.
3. Press: pitch MacStories / MacSources / 9to5Mac once screenshots + site are
   polished (Dot's social proof comes from exactly these).
4. GitHub repo README badge → site; site → repo (bidirectional links).

## Measurement

- Google Search Console + Bing Webmaster from day 1; submit sitemap.
- Ahrefs Webmaster Tools on mousugu.app (free tier covers audit + rank data
  the API plan does not).
- Privacy-respecting analytics only (Plausible or self-hosted Umami) — the
  "talks to no server" claim must survive the marketing site.

## Phases

1. **Phase 1 — foundation (1 day):** register `mousugu.app` (blocker), build
   landing EN/ES in Astro with all on-page rules, robots + sitemap + JSON-LD,
   deploy to Cloudflare Pages, wire GSC, move appcast to `/appcast.xml`.
2. **Phase 2 — week 1:** og-image, three `/vs/` pages, directory listings,
   Show HN + Product Hunt launch.
3. **Phase 3 — ongoing:** one how-to post per month targeting a validated
   long-tail query; changelog entry per release; monthly GSC query review →
   promote queries with impressions into dedicated pages.
