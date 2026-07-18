# Marketing & design assets

Source images behind the website and installer. Generated/derived files live
where they are consumed; the editable sources live here.

## Website hero

- `hero.png` — the source: a real full-screen capture of the menu-bar chip and
  the open popover (1558×942).
- `../website/public/hero.webp` — the served asset: `hero.png` encoded at native
  resolution with `cwebp -q 95` (~100 KB, the hero's LCP element). High quality
  keeps the popover's UI text crisp; native width covers 2× on Retina.

To regenerate the web asset after replacing `hero.png`:

```sh
cwebp -q 95 -m 6 assets/hero.png -o website/public/hero.webp
```

## Tooling

- `../scripts/generate_hero_shot.swift` — utility that composites a raw
  full-screen capture (popover + optional menu-bar chip) onto the brand
  gradient with a dot-grid and soft shadow (CleanShot/OpenScreen "menu opened"
  look). Not used for the current hero; kept for producing composed shots.
- `../scripts/generate_dmg_background.swift` — renders
  `../Config/dmg-background@2x.png`, the branded DMG installer backdrop.
