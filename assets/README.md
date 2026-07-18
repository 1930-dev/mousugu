# Marketing & design assets

Source images behind the website and installer. Generated/derived files live
where they are consumed; the editable sources live here.

## Website hero

- `hero-source.png` — original hand-composed shot (menu-bar chip + open
  popover on the brand gradient), clock reading 3:07.
- `hero-shot.png` — same composition with the menu-bar clock patched to 4:20;
  the shipped source of the hero.
- `../website/public/hero.webp` — the served asset: `hero-shot.png` resized to
  1600×1066 and encoded with `cwebp -q 84` (~44 KB, the hero's LCP element).

To regenerate the web asset after editing `hero-shot.png`:

```sh
sips --resampleWidth 1600 assets/hero-shot.png --out /tmp/hero.png
cwebp -q 84 /tmp/hero.png -o website/public/hero.webp
```

## Tooling

- `../scripts/generate_hero_shot.swift` — utility that composites a raw
  full-screen capture (popover + optional menu-bar chip) onto the brand
  gradient with a dot-grid and soft shadow (CleanShot/OpenScreen "menu opened"
  look). Kept for producing future shots from a fresh capture.
- `../scripts/generate_dmg_background.swift` — renders
  `../Config/dmg-background@2x.png`, the branded DMG installer backdrop.
